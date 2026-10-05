"""A small pipe-based search language over the event store, in the style of
Splunk's SPL.

    host=WKS-0014 event_type=dns | stats count, dc(domain) by host
    event_type=auth outcome=failure | timechart span=1h count by host
    bytes_sent>1000000 NOT dst_ip=10.10.* | top limit=5 dst_ip

The first segment filters events:

* `field=value` (case-insensitive, `*` wildcards), `field!=value`, and
  numeric `field>N`, `>=`, `<`, `<=`;
* a bare word matches anywhere in any text field (`powershell`, `"-enc"`);
* terms are ANDed; `OR` between two terms joins them; `NOT` negates the
  next term; `earliest=-6h` / `latest=-1h` are relative to the newest event.

Commands after a pipe: `where`, `stats`, `timechart`, `top`, `rare`, `sort`,
`head`, `tail`, `table`, `dedup`, `rename`.

It is an interpreter over a DataFrame, never SQL or `eval`, so a query can
only read and reshape events. Ground-truth columns are dropped before the
first term runs.
"""

from __future__ import annotations

import fnmatch
import re
import shlex
from dataclasses import dataclass, field

import pandas as pd

HIDDEN_COLUMNS = ("scenario_tag", "scenario_id", "campaign_id")
TEXT_FIELDS = ("user", "host", "src_ip", "dst_ip", "src_country", "action", "outcome", "process_name",
               "command_line", "domain", "event_type", "direction", "protocol")
AGGREGATES = ("count", "dc", "sum", "avg", "min", "max", "median")
MAX_SERIES = 8
COMPARISON = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)(!=|>=|<=|=|>|<)(.*)$", re.S)
RELATIVE = re.compile(r"^-(\d+)([smhd])$")
UNITS = {"s": "seconds", "m": "minutes", "h": "hours", "d": "days"}

SAVED_SEARCHES = {
    "Failed logins by host, per hour": "event_type=auth outcome=failure | timechart span=1h count by host",
    "Top talkers by bytes out": "event_type=network direction=outbound | stats sum(bytes_sent) as bytes_out, count by host | sort -bytes_out | head 10",
    "Encoded PowerShell": 'process_name=powershell.exe "-enc" | table ts, host, user, command_line',
    "Rare domains": "event_type=dns | rare limit=15 domain",
    "Accounts logging in from several countries": "event_type=auth outcome=success | stats dc(src_country) as countries, values(src_country) as seen_in by user | where countries > 1 | sort -countries",
    "Inbound ports touched per source": "event_type=network direction=inbound | stats dc(port) as ports, count by src_ip, host | where ports >= 5 | sort -ports",
}


class SearchError(ValueError):
    pass


@dataclass
class SearchResult:
    frame: pd.DataFrame
    chart: str = "none"                 # "timechart" | "bar" | "none"
    x: str | None = None                # timechart: the time column; bar: the category column
    y: list[str] = field(default_factory=list)
    scanned: int = 0                    # events the first segment looked at
    matched: int = 0                    # events it kept


# --- parsing ------------------------------------------------------------------

def split_pipeline(query: str) -> list[str]:
    """Split on pipes that are not inside quotes."""
    parts, buf, quote = [], [], None
    for ch in query:
        if quote:
            buf.append(ch)
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            buf.append(ch)
        elif ch == "|":
            parts.append("".join(buf).strip())
            buf = []
        else:
            buf.append(ch)
    if quote:
        raise SearchError("Unclosed quote.")
    parts.append("".join(buf).strip())
    if any(p == "" for p in parts[1:]):
        raise SearchError("Empty command after a pipe.")
    return parts


def _tokens(segment: str) -> list[str]:
    try:
        return shlex.split(segment, posix=True)
    except ValueError as exc:
        raise SearchError(f"Could not read the query: {exc}.") from None


def _number(value: str):
    try:
        return float(value)
    except ValueError:
        return None


def _match_value(series: pd.Series, value: str) -> pd.Series:
    text = series.astype("string").str.lower()
    value = value.lower()
    if "*" in value or "?" in value:
        pattern = fnmatch.translate(value)
        return text.str.match(pattern, na=False)
    numeric = _number(value)
    if numeric is not None and pd.api.types.is_numeric_dtype(series):
        return series == numeric
    return (text == value).fillna(False).astype(bool)


def _comparison(df: pd.DataFrame, name: str, op: str, value: str) -> pd.Series:
    if name not in df.columns:
        raise SearchError(f"Unknown field `{name}`. Fields: {', '.join(c for c in df.columns if c != 'ts')}.")
    series = df[name]
    if op in ("=", "!="):
        hit = _match_value(series, value)
        return ~hit if op == "!=" else hit
    numeric = _number(value)
    if name == "ts":
        bound = pd.to_datetime(value, errors="coerce")
        if pd.isna(bound):
            raise SearchError(f"`{value}` is not a time.")
        left, right = series, bound
    elif numeric is None:
        raise SearchError(f"`{name}{op}{value}` needs a number.")
    else:
        left, right = pd.to_numeric(series, errors="coerce"), numeric
    result = {">": left > right, ">=": left >= right, "<": left < right, "<=": left <= right}[op]
    return result.fillna(False).astype(bool)


def _bare(df: pd.DataFrame, word: str) -> pd.Series:
    word = word.lower()
    wildcard = "*" in word or "?" in word
    pattern = fnmatch.translate(f"*{word}*") if wildcard else None
    hit = pd.Series(False, index=df.index)
    for column in TEXT_FIELDS:
        if column not in df.columns:
            continue
        text = df[column].astype("string").str.lower()
        hit |= (text.str.match(pattern, na=False) if wildcard else text.str.contains(word, regex=False, na=False))
    return hit


def _relative(value: str, newest: pd.Timestamp) -> pd.Timestamp:
    if value == "now":
        return newest
    match = RELATIVE.match(value)
    if not match:
        absolute = pd.to_datetime(value, errors="coerce")
        if pd.isna(absolute):
            raise SearchError(f"`{value}` is not a time. Use a relative time like -6h, or now.")
        return absolute
    amount, unit = match.groups()
    return newest - pd.Timedelta(**{UNITS[unit]: int(amount)})


def _filter(df: pd.DataFrame, segment: str) -> pd.DataFrame:
    tokens = _tokens(segment)
    if not tokens or tokens == ["*"]:
        return df
    newest = df["ts"].max() if "ts" in df.columns and not df.empty else pd.Timestamp.now()
    mask = pd.Series(True, index=df.index)
    pending_or: pd.Series | None = None
    negate = False
    i = 0
    while i < len(tokens):
        token = tokens[i]
        upper = token.upper()
        if upper == "NOT":
            negate = not negate
            i += 1
            continue
        if upper == "AND":
            i += 1
            continue
        if upper == "OR":
            raise SearchError("`OR` must sit between two terms.")
        match = COMPARISON.match(token)
        if match and match.group(1) in ("earliest", "latest") and "ts" in df.columns:
            bound = _relative(match.group(3), newest)
            term = df["ts"] >= bound if match.group(1) == "earliest" else df["ts"] <= bound
        elif match:
            term = _comparison(df, *match.groups())
        else:
            term = _bare(df, token)
        if negate:
            term = ~term
            negate = False
        # `a OR b` binds tighter than the implicit AND around it.
        if pending_or is not None:
            term = pending_or | term
            pending_or = None
        if i + 1 < len(tokens) and tokens[i + 1].upper() == "OR":
            if i + 2 >= len(tokens):
                raise SearchError("`OR` must sit between two terms.")
            pending_or = term
            i += 2
            continue
        mask &= term
        i += 1
    if negate:
        raise SearchError("`NOT` must be followed by a term.")
    return df[mask]


# --- commands -------------------------------------------------------------------

def _fields(text: str) -> list[str]:
    return [f.strip() for f in re.split(r"[,\s]+", text.strip()) if f.strip()]


def _require(df: pd.DataFrame, names: list[str]) -> None:
    missing = [n for n in names if n not in df.columns]
    if missing:
        raise SearchError(f"Unknown field `{missing[0]}`. Available here: {', '.join(df.columns)}.")


AGG_SPEC = re.compile(r"(count|dc|sum|avg|min|max|median|values)(?:\(\s*([A-Za-z_][A-Za-z0-9_]*)?\s*\))?(?:\s+as\s+([A-Za-z_][A-Za-z0-9_]*))?", re.I)


def _parse_aggregates(text: str) -> list[tuple[str, str | None, str]]:
    specs = []
    for chunk in [c.strip() for c in text.split(",") if c.strip()]:
        match = AGG_SPEC.fullmatch(chunk)
        if not match:
            raise SearchError(f"Can't read `{chunk}`. Use count, dc(f), sum(f), avg(f), min(f), max(f), median(f) or values(f), optionally `as name`.")
        func, arg, alias = match.group(1).lower(), match.group(2), match.group(3)
        if func != "count" and not arg:
            raise SearchError(f"`{func}` needs a field, e.g. {func}(bytes_sent).")
        specs.append((func, arg, alias or (func if func == "count" and not arg else f"{func}({arg})")))
    return specs


def _aggregate(df: pd.DataFrame, specs, by: list[str]) -> pd.DataFrame:
    _require(df, [a for _, a, _ in specs if a] + by)
    grouped = df.groupby(by, dropna=True, sort=False) if by else None
    columns = {}
    for func, arg, alias in specs:
        source = grouped if grouped is not None else df
        if func == "count":
            value = source[arg].count() if arg else (source.size() if grouped is not None else len(df))
        elif func == "dc":
            value = source[arg].nunique()
        elif func == "values":
            value = (source[arg].agg(lambda s: ", ".join(sorted(map(str, s.dropna().unique()))[:10]))
                     if grouped is not None else ", ".join(sorted(map(str, df[arg].dropna().unique()))[:10]))
        else:
            numeric = (pd.to_numeric(df[arg], errors="coerce"))
            target = numeric.groupby([df[b] for b in by], dropna=True, sort=False) if by else numeric
            value = getattr(target, {"avg": "mean"}.get(func, func))()
        columns[alias] = value
    if grouped is None:
        return pd.DataFrame({k: [v] for k, v in columns.items()})
    return pd.DataFrame(columns).reset_index()


def _split_by(text: str) -> tuple[str, list[str]]:
    parts = re.split(r"\s+by\s+", text, maxsplit=1, flags=re.I)
    return parts[0], (_fields(parts[1]) if len(parts) > 1 else [])


def _cmd_stats(df, args, result):
    head, by = _split_by(args)
    if not head.strip():
        raise SearchError("`stats` needs at least one aggregate, e.g. `stats count by host`.")
    out = _aggregate(df, _parse_aggregates(head), by)
    if by and len(out.columns) > len(by):
        result.chart, result.x, result.y = "bar", by[0], [c for c in out.columns if c not in by and pd.api.types.is_numeric_dtype(out[c])][:1]
    return out


def _cmd_timechart(df, args, result):
    span = "1h"
    match = re.search(r"\bspan=(\d+[smhd])\b", args)
    if match:
        amount, unit = match.group(1)[:-1], match.group(1)[-1]
        span = amount + {"s": "s", "m": "min", "h": "h", "d": "D"}[unit]
        args = args.replace(match.group(0), "")
    head, by = _split_by(args)
    specs = _parse_aggregates(head.strip() or "count")
    if len(specs) != 1:
        raise SearchError("`timechart` takes one aggregate.")
    if len(by) > 1:
        raise SearchError("`timechart` splits by at most one field.")
    if "ts" not in df.columns:
        raise SearchError("`timechart` needs the `ts` field.")
    work = df.assign(_time=df["ts"].dt.floor(span))
    func, arg, alias = specs[0]
    if by:
        _require(work, by)
        totals = work[by[0]].value_counts()
        keep = set(totals.index[:MAX_SERIES])
        work = work.assign(**{by[0]: work[by[0]].where(work[by[0]].isin(keep), "OTHER")})
    out = _aggregate(work, [(func, arg, alias)], ["_time"] + by)
    if by:
        out = out.pivot_table(index="_time", columns=by[0], values=alias, aggfunc="sum", fill_value=0)
        out.columns = [str(c) for c in out.columns]
        # Biggest series first, OTHER always last.
        order = sorted((c for c in out.columns if c != "OTHER"), key=lambda c: -out[c].sum())
        out = out[order + (["OTHER"] if "OTHER" in out.columns else [])].reset_index()
    if not out.empty:
        full = pd.date_range(df["ts"].min().floor(span), df["ts"].max().floor(span), freq=span)
        out = out.set_index("_time").reindex(full, fill_value=0).rename_axis("_time").reset_index()
    out = out.rename(columns={"_time": "time"})
    result.chart, result.x, result.y = "timechart", "time", [c for c in out.columns if c != "time"]
    return out


def _cmd_top(df, args, result, ascending=False):
    limit = 10
    match = re.search(r"\blimit=(\d+)\b", args)
    if match:
        limit = int(match.group(1))
        args = args.replace(match.group(0), "")
    head, by = _split_by(args)
    names = _fields(head)
    if not names:
        raise SearchError("`top` needs a field, e.g. `top dst_ip`.")
    _require(df, names + by)
    counts = df.groupby(names + by, dropna=True).size().rename("count").reset_index()
    total = counts["count"].sum() if not by else counts.groupby(by)["count"].transform("sum")
    counts["percent"] = (100 * counts["count"] / total).round(1)
    counts = counts.sort_values("count", ascending=ascending, kind="stable")
    counts = counts.groupby(by, sort=False).head(limit) if by else counts.head(limit)
    result.chart, result.x, result.y = "bar", names[0], ["count"]
    return counts.reset_index(drop=True)


def _cmd_where(df, args, result):
    tokens = _tokens(args)
    if not tokens:
        raise SearchError("`where` needs a condition, e.g. `where count > 10`.")
    # Re-join "field op value" written with spaces: `count > 10` -> `count>10`.
    joined, i = [], 0
    while i < len(tokens):
        if i + 1 < len(tokens) and tokens[i + 1] in ("=", "==", "!=", ">", ">=", "<", "<="):
            if i + 2 >= len(tokens):
                raise SearchError(f"`where {' '.join(tokens)}` is missing a value.")
            op = "=" if tokens[i + 1] == "==" else tokens[i + 1]
            joined.append(f"{tokens[i]}{op}{tokens[i + 2]}")
            i += 3
        else:
            joined.append(tokens[i].replace("==", "="))
            i += 1
    for token in joined:
        if token.upper() not in ("AND", "OR", "NOT") and not COMPARISON.match(token):
            raise SearchError(f"`where` only compares fields: `{token}` isn't a comparison.")
    return _filter(df, " ".join(shlex.quote(t) for t in joined))


def _cmd_sort(df, args, result):
    keys = _fields(args.replace(",", " "))
    if not keys:
        raise SearchError("`sort` needs a field, e.g. `sort -count`.")
    names = [k.lstrip("+-") for k in keys]
    _require(df, names)
    return df.sort_values(names, ascending=[not k.startswith("-") for k in keys], kind="stable", na_position="last")


def _count(args: str, default: int = 10) -> int:
    args = args.strip()
    if not args:
        return default
    if not args.isdigit():
        raise SearchError(f"Expected a number of rows, got `{args}`.")
    return int(args)


def _cmd_table(df, args, result):
    names = _fields(args)
    _require(df, names)
    result.chart = "none"
    return df[names]


def _cmd_dedup(df, args, result):
    names = _fields(args)
    _require(df, names)
    return df.drop_duplicates(subset=names)


def _cmd_rename(df, args, result):
    match = re.fullmatch(r"\s*([A-Za-z_][\w()]*)\s+as\s+([A-Za-z_]\w*)\s*", args, flags=re.I)
    if not match:
        raise SearchError("Use `rename old as new`.")
    _require(df, [match.group(1)])
    if result.x == match.group(1):
        result.x = match.group(2)
    result.y = [match.group(2) if y == match.group(1) else y for y in result.y]
    return df.rename(columns={match.group(1): match.group(2)})


COMMANDS = {
    "where": _cmd_where,
    "stats": _cmd_stats,
    "timechart": _cmd_timechart,
    "top": _cmd_top,
    "rare": lambda df, a, r: _cmd_top(df, a, r, ascending=True),
    "sort": _cmd_sort,
    "head": lambda df, a, r: df.head(_count(a)),
    "tail": lambda df, a, r: df.tail(_count(a)),
    "table": _cmd_table,
    "dedup": _cmd_dedup,
    "rename": _cmd_rename,
}


def run(events: pd.DataFrame, query: str, limit: int = 5000) -> SearchResult:
    """Run `query` over `events`; at most `limit` rows come back."""
    query = (query or "").strip()
    segments = split_pipeline(query or "*")
    df = events.drop(columns=[c for c in HIDDEN_COLUMNS if c in events.columns])
    result = SearchResult(frame=df, scanned=len(df))
    first = segments[0]
    if first.split(" ", 1)[0].lower() in COMMANDS and "=" not in first.split(" ", 1)[0]:
        raise SearchError(f"Start with search terms (or `*`), then pipe: `* | {first}`.")
    df = _filter(df, first)
    result.matched = len(df)
    for segment in segments[1:]:
        name, _, args = segment.partition(" ")
        command = COMMANDS.get(name.lower())
        if command is None:
            raise SearchError(f"Unknown command `{name}`. Commands: {', '.join(COMMANDS)}.")
        df = command(df, args, result)
    if result.chart == "bar" and (result.x not in df.columns or not result.y or result.y[0] not in df.columns):
        result.chart = "none"
    result.frame = df.head(limit).reset_index(drop=True)
    return result
