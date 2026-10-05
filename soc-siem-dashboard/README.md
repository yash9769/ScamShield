# SOC/SIEM Dashboard

A self-contained SIEM/SOC analytics project. It has a synthetic security-event
generator with multi-stage attack campaigns, a Sigma-style rule engine, an
Isolation Forest anomaly detector, alert correlation into incidents,
risk-based entity scoring, IOC extraction, playbook-driven response with
exportable incident reports, incident attack graphs, a pipe-based search
language, threat intel with retro-hunting, alert suppression, a streaming
live monitor, threshold tuning against ground truth, a read-only
threat-hunting console, and a thirteen-page Streamlit dashboard over all
of it. Every detection is graded twice:
against the generator's own ground truth, and against **NSL-KDD**, a real
labeled intrusion-detection benchmark.

Built as a portfolio/learning project for data analysis & visualization, not a
production SIEM — see [Honest limitations](#honest-limitations).

## Headline results

Measured, not asserted — reproduce with the snippet in [Tests](#tests).

| | Result |
|---|---|
| Rule-covered techniques caught | **100%** on every one of 20 seeds — by construction, see below |
| DNS beaconing caught (anomaly detection only — no rule covers it) | **100%** on every one of 20 seeds |
| Anomaly-detector alert precision | **82%** mean across 20 seeds (range 70–100%) |
| Multi-stage campaigns reconstructed as one incident | **39 / 40** across 20 seeds |
| Alert → incident compression | ~2× fewer things to look at |
| Live monitor, 3 × 24 simulated hours | **143 / 143** injected attacks caught, **0** repeat rule alerts per attack |

**On NSL-KDD**, the test set holds 17 attack types (3,750 of 12,833 attack
records) that never appear in training:

| | Recall, attack types seen in training | Recall, types never seen |
|---|---|---|
| Random Forest (supervised) | **77%** | 25% |
| Isolation Forest (unsupervised, contamination 0.10) | 16% | **42%** |

Supervision memorizes the attacks you already know; anomaly detection is how
you notice the ones you don't. That is the argument for running both, and the
reason this project pairs rules with an anomaly detector.

## Quickstart (run it locally)

**You need:** Python 3.11+ and pip. No database server, API keys or Docker.
The one network call is the NSL-KDD benchmark download (see below).

```bash
# 1. Get the code (this project lives in a subfolder of the ScamShield repo)
git clone https://github.com/yash9769/ScamShield.git
cd ScamShield
git checkout claude/soc-siem-dashboard
cd soc-siem-dashboard

# 2. Install
python3 -m venv .venv && source .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# 3. Build the data (synthetic logs + attacks, then rules, anomaly model, correlation)
python3 scripts/generate_data.py          # writes data/soc.db; add --campaigns 2 for more kill chains
python3 scripts/run_detection.py

# 4. Open the dashboard
streamlit run dashboard/app.py            # http://localhost:8501

# Optional: run the tests
pytest                                    # 130 tests, offline, ~30 s
```

Step 3 can be skipped: open the dashboard and use **Generate / regenerate demo
data** on the Overview page. Re-running `generate_data.py` overwrites
`data/soc.db`, which resets incident notes, response checkboxes, the
watchlist and suppressions.

**Dataset Validation** downloads NSL-KDD (about 20 MB, once) from GitHub into
`data/raw/` and then works offline. Every other page, and all tests, need no
network. If the download is blocked, put `KDDTrain+.txt` and `KDDTest+.txt`
in `data/raw/` by hand.

**Troubleshooting**

- `streamlit: command not found`: activate the virtualenv, or run
  `python3 -m streamlit run dashboard/app.py`.
- Port 8501 is busy: add `--server.port 8502`.
- Pages say "No data yet": run step 3, or use the Overview page's generate panel.
- Edited code but the page didn't change: stop and restart Streamlit.

The Overview page's **Generate / regenerate demo data** panel does the same
from the browser. Detection Coverage can re-run detection with a different
anomaly contamination or correlation window.

## Dashboard

**Monitor**

| Page | What it's for |
|---|---|
| Overview | KPIs, event volume, alerts by severity, riskiest entities, top incidents |
| Incidents | Correlated alerts with an ATT&CK kill-chain strip, a timeline, an attack graph, entities and member alerts; then the case work: extracted IOCs, decoded PowerShell, a response checklist, analyst notes, and a one-file HTML incident report. Changing an incident's status changes its member alerts too |
| Alerts & Triage | Every individual detection, with inline status editing, linked raw events, decoded PowerShell payloads, CSV export, and "suppress alerts like this" |
| Live Monitor | The pipeline as a stream: a simulated clock, random attack injection, rules on a rolling buffer, the anomaly model scoring each hour as it closes, and live recall against the answer key |

**Investigate**

| Page | What it's for |
|---|---|
| Search | A pipe-based query language over the raw events in the style of Splunk's SPL (`stats`, `timechart`, `top`, `where`…), with charts that follow the shape of the result |
| Entity Investigation | One host or account: risk, hour-by-day activity heatmap with alert hours outlined, a peer-group comparison, and everything it's involved in |
| Threat Hunting | Read-only SQL over the event store with seven saved, hypothesis-driven hunts. Locked down: see [Threat hunting](#threat-hunting) |
| Threat Intel | Feed and watchlist matches against every event, whether an alert covered them, a retro-hunt for "who else touched this, and since when", and DGA-style domain scoring |
| Threat Map | Event volume per country, highlighting any country that carried traffic from a known-malicious IP |

**Evaluate**

| Page | What it's for |
|---|---|
| Detection Coverage | Recall per technique (and which detector caught it), precision per detector, time-to-detect, an ATT&CK coverage grid that marks blind spots, correlation quality, and an ATT&CK Navigator layer export |
| Detection Tuning | Each rule re-run across a range of thresholds and scored on recall and false positives; precision@k and recall@k for the anomaly alert budget; suppressions with their hit counts and a ground-truth check |
| Anomaly Detection | Live contamination slider, top flagged host-hours, and a "why this one" chart in multiples of the dataset average |
| Dataset Validation | Isolation Forest vs. Random Forest on NSL-KDD: seen vs. unseen attack types, precision–recall curves, and per-category recall |

## How it works

```
generator ──► events ──► rules ─────────┐
                    └──► anomaly ───────┼──► alerts ──► correlation ──► incidents
                                        │                    │
                    ground truth ───────┴──► evaluation ◄────┘
```

### The synthetic environment

39 hosts (DCs, web, DB, file servers, a VPN gateway, 30 workstations) and 40
accounts generate auth, network, DNS, and process logs on a business-hours
curve. Every user has one consistent home country, and baseline PowerShell is
everyday admin scripting, so neither looks suspicious by accident.

Seven standalone attack scenarios are layered on top: brute force, port scan,
impossible travel, data exfiltration, DNS beaconing, encoded PowerShell, and
lateral movement. There is also a **kill-chain campaign** that chains six
stages through one intruder's footprint:

1. scan the VPN gateway from the attacker's address;
2. brute-force an account through it;
3. run hidden, base64-encoded PowerShell on a workstation as that account;
4. beacon to a C2 domain;
5. fan out to four to six servers;
6. exfiltrate from a data store back to the attacker's address.

Each event carries ground truth: `scenario_tag` (technique), `scenario_id`
(instance) and `campaign_id`. Detection never reads these columns. Threat
hunting can't see them either; they read as NULL there.

### Detection

| Rule | ATT&CK | Logic |
|---|---|---|
| `brute_force` | T1110 | ≥ 5 failures from one source against one host in 10 min. A success in the same window escalates it to critical |
| `port_scan` | T1595 | ≥ 10 distinct inbound ports from one source to one host in 5 min |
| `impossible_travel` | T1078 | Consecutive successful logins whose implied travel speed exceeds 900 km/h (haversine distance ÷ gap) |
| `lateral_movement` | T1021 | One internal address logging into ≥ 4 distinct hosts in 30 min |
| `suspicious_powershell` | T1059.001 | `-e`/`-enc`/`-EncodedCommand` followed by a long base64 blob, or an `IEX … DownloadString` cradle. Admin scripts don't match |
| `data_exfiltration` | T1041 | ≥ 60 MB outbound to a non-internal address within a 10-min sliding window |

Rules are YAML (metadata + parameters) with Sigma-style field modifiers
(`src_ip|startswith`, `process_name|in`, `|contains`, `|re`). The matching
logic lives in Python, keyed by `logic.type`, the same split real Sigma
backends make. A windowed rule fires the moment its threshold is crossed. The
rest of that window then becomes part of the same alert instead of paging
again, and after the window the rule re-arms.

The **anomaly detector** scores every active host-hour. Its eight features
include DNS query count, distinct domains, outbound bytes, and the standard
deviation of the gaps between DNS queries; that last one is the beaconing
signal, since people browse irregularly and implants check in on a timer. The
model is an Isolation Forest, and each anomaly comes with a plain-language
reason and, where it fits, an ATT&CK mapping.

### Correlation and risk

Two alerts belong to the same **incident** when they share a host, account, or
external IP and fired within 3 h of each other. Grouping is transitive
(union-find), so a scan → brute force → PowerShell → lateral movement →
exfiltration chain is one incident even though its first and last alerts share
nothing directly. Internal addresses are resolved to host names through the
asset inventory, so `10.10.10.12` and `WKS-0012` count as the same machine.
Three or more ATT&CK tactics in one incident escalate it to critical.

**Entity risk** follows risk-based alerting. Each alert adds its severity
weight to every entity it involves, and that risk halves every 24 h.

### Evaluation

Detection Coverage grades the stack the way a detection-engineering team
would:

- recall per technique, split by what caught it (rules / anomaly / both);
- precision per detector (did the alert touch real attack activity?);
- time from an attack's first event to its first alert;
- whether each campaign's detected stages ended up in one incident, and
  whether incidents mix unrelated attacks.

Rule recall is 100% *by construction*: every injected rule-covered scenario is
generated to cross its rule's threshold. That number checks the plumbing, not
the rules' worth, which is why NSL-KDD exists in this project.

### Threat hunting

Hunts execute SQL a person typed, so there are three independent guards:

1. The database is opened read-only (`mode=ro`).
2. An SQLite authorizer allows only SELECT, column reads, and function calls,
   refusing every write, `ATTACH`, and `PRAGMA` before anything runs.
3. A progress handler stops any query after 5 s.

Stacked statements are refused, and the ground-truth columns read as NULL.
Hunts also get SQL functions SQLite doesn't ship with: `entropy()`,
`domain_label()`, `is_internal()`, and a `stddev()` aggregate. The saved
"beacon-like DNS cadence" hunt uses window functions to measure query-gap
regularity per host/domain pair.

### Response

An incident's **IOCs** are the external addresses its alerts involve, the URLs
and domains inside its decoded PowerShell (`-enc` takes base64 of UTF-16LE
text), and any domain its hosts resolved that at most two hosts in the whole
environment ever resolved. A SaaS domain every laptop queries indicates
nothing.

**Response steps** come from ATT&CK-keyed playbooks (`response/playbooks.yml`)
in investigate → contain → eradicate → recover order. Each step is filled in
with the entities of *its own technique's* alerts, not the incident's union:
an incident's host list includes every machine a port scan touched, and
"isolate the host" has to mean the one that ran the payload. A step whose
entities are absent (block an IP, when there is no IP) is not offered.
Checked steps and notes are stored with the incident, and the HTML report
carries both.

### Attack graph

Each incident gets a graph of who did what to whom. Edges come from the
evidence events rather than the alerts' entity lists, because an entity list
has no direction: an inbound connection or logon points source → host, an
outbound transfer host → external IP, a DNS lookup host → domain. Nodes sit in
swimlanes (external, hosts, accounts) and run left to right in the order they
first appear. Order, not clock time: a fan-out to six servers in fifteen
minutes would otherwise pile into one corner after a two-hour gap. On the
campaign incident it reads as the attack happened: scan and brute force on the
VPN gateway, the account, PowerShell on a workstation, C2, lateral movement,
exfiltration back to the attacker's address.

### Search

```
event_type=auth outcome=failure | timechart span=1h count by host
event_type=network direction=outbound | stats sum(bytes_sent) as bytes_out by host | sort -bytes_out | head 10
bytes_sent>1000000 NOT dst_ip=10.10.* | top limit=5 dst_ip
```

Field terms with wildcards and numeric comparisons, bare words across all text
fields, `NOT`, `OR`, and relative time (`earliest=-6h`), then `stats` (count,
dc, sum, avg, min, max, median, values), `timechart`, `top`, `rare`, `where`,
`sort`, `head`, `tail`, `table`, `dedup` and `rename`. It is an interpreter
over a DataFrame, never SQL or `eval`, so a query can only read, and the
ground-truth columns are dropped before it runs. `timechart` keeps the eight
biggest series (one per categorical color) and folds the rest into a grey
OTHER, so colors never repeat.

### Threat intel and suppression

The **feed** stands in for an IP-reputation list. It is built from the
inventory's `known_malicious` flag, set before any attack ran, and attacks
draw from that pool 70% of the time, so the feed covers some attacks and not
others. On the default dataset it knew 4 of the 5 attacker addresses. The
**retro-hunt** searches every event for an indicator. For the campaign's
attacker address it finds outbound contact from a workstation two days before
the intrusion began. Analysts add an incident's IOCs to a **watchlist** with
one click, and it survives detection re-runs.

**Suppressions** are exceptions for known-benign activity, written from an
alert: a detector (or any) plus an entity pattern, a required reason, and an
expiry. Matching alerts are still stored, marked `suppressed`, so the record
is auditable, but they open no incident, add no risk, and don't count as
detections. Both the form and the Tuning page check suppressions against
ground truth and warn when one would hide real attack activity.

### Streaming

The Live Monitor replays the pipeline as a SOC would see it. Rules run on a
rolling 90-minute buffer every tick. The anomaly model is trained once on the
stored history and scores each host-hour as it closes, so rule alerts arrive
within minutes while beaconing (anomaly-only) waits for the hour to end. An
alert is new only if the event that triggered it isn't already evidence in an
earlier alert from the same rule on the same entity.

### Tuning

Every threshold trades quiet attacks against a noisy queue. Detection Tuning
re-runs a rule at each value of one parameter and scores the result: brute
force holds 100% recall with zero false positives from 2 to 8 failures; at 1
every typo alerts, and above 8 the attacks slip under. Lateral movement goes
from 4 alerts to 304 when its threshold drops from 2 hosts to 1. Where a
sweep is perfectly flat, the page says so: that is the synthetic background
being too clean, not the rule being robust. For anomaly detection the knob is
the alert budget. Precision@20 is 80%; coverage stops growing at k ≈ 46,
where precision has fallen to about 45%.

## Things this project got wrong first

Each of these was found by testing in a real browser or by measuring, and
each is now covered by a regression test:

- **Impossible-travel false positives.** Background logins once picked a fresh
  random country per login, so ordinary users flip-flopped countries and the
  rule fired 40 times on 8 true events. Fixed with one home country per user.
- **A kill chain split in two.** The lateral-movement rule's evidence stopped
  at the 4th target, so servers reached afterwards were missing from the alert
  and correlation couldn't join on them. The same `break` meant a source that
  attacked twice only ever alerted once.
- **One exfiltration, two alerts.** Fixed 10-minute buckets split a transfer at
  the boundary. Replaced with a sliding window plus suppression.
- **A misleading timeline.** Anomaly alerts are stamped at the start of their
  hour, which drew them *before* the activity they flagged. They're now drawn
  as the hour they cover.
- **Stale triage edits.** Streamlit's data editor keeps positional edits across
  reruns. Once a status change moved a row out of the current filter, the edit
  would have landed on whichever incident took its place. The editor is now
  re-keyed after every applied edit, and that was verified by driving the real
  grid in Chromium.
- **Caches that never invalidated on writes.** `st.cache_data` ignores
  underscore-prefixed arguments, so the database-mtime cache key was silently
  never part of the key.
- **The live monitor alerted twice on one attack.** Dedupe keyed on a rule's
  first evidence event; once that event slid out of the rolling buffer, the
  remaining events re-matched with a new "first" event. Removing the fix makes
  its test fail with three repeats.
- **Response advice aimed at the wrong machines.** Playbook steps were first
  filled in from the incident's whole entity set, so "isolate" listed every
  server the port scan had probed. Steps are now scoped per technique.
- **A suppression that hid an attack.** While testing the suppression flow,
  a suppression written from whichever alert happened to be selected hid two
  alerts on WKS-0003 that were real beaconing. That is the classic way
  suppression goes wrong, so the form and the Tuning page now warn when a
  suppression matches alerts that touched attack activity.
- **The search chart reused a color.** `OTHER` took a categorical slot, so
  the ninth series wrapped around to the first series' blue. `OTHER` is now
  grey and takes no slot, and series are ordered by volume.
- **The tuning chart marked the wrong default.** On a category axis Plotly
  reads the string `"5"` as category index 5, which put the "current" marker
  on 6. Caught in the screenshot, not by a test.

## Honest limitations

- **Not a real SIEM.** There's no log ingestion, retention, multi-tenancy, or
  auth on the dashboard. It demonstrates the analysis and detection
  methodology, not a deployable product.
- **The generator and detectors share an author.** That's why the NSL-KDD
  comparison exists. It's also why the rule-recall figure is labeled "by
  construction" rather than presented as a result.
- **Anomaly credit is an upper bound.** An anomaly alert links every event its
  host produced that hour, so it's credited with any attack active on that
  host in that hour.
- **NSL-KDD's test set is ~57% attacks**, far above any real network. Its
  numbers describe relative strengths, not deployable false-positive rates.
- **The correlation window is a tradeoff.** The one campaign of 40 that wasn't
  reconstructed lost a follow-on impossible-travel alert that fired 4 h after
  the last stage, just past the 3 h window. Widening the window catches that
  but merges more unrelated activity. Detection Coverage lets you try it.
- **T1568 (Dynamic Resolution) has no detector.** The coverage grid shows it
  as a blind spot rather than hiding it.

## Project layout

```
src/socdash/
  generator/        entities (inventory), events (single emitters), scenarios (attacks + kill chain)
  detection/        rules/*.yml, rule_engine, anomaly, entities (enrichment), correlation, risk, ioc,
                    graph (incident attack graph), suppression
  response/         playbooks.yml, plan(), report.py (self-contained HTML incident report)
  datasets/         nsl_kdd — loader, Isolation Forest + Random Forest evaluation, seen/unseen split
  storage/db.py     SQLite schema (events, alerts, incidents, watchlist, suppressions), in-place migration
  evaluation.py     grading against ground truth
  hunting.py        read-only SQL runner, custom SQL functions, saved hunts
  tuning.py         rule threshold sweeps, anomaly alert-budget curve
  search.py         pipe-based search language (stats, timechart, top, where, ...)
  intel.py          reputation feed, sightings, retro-hunt sweep, DGA-style domain scoring
  live.py           streaming simulator: rolling-buffer rules, hourly online anomaly scoring
  navigator.py      ATT&CK Navigator layer export
  pipeline.py       generate_and_store / detect_and_store — shared by CLI and dashboard
  mitre.py, geo.py  ATT&CK catalog + tactic order; haversine + country centroids
dashboard/          app.py (sectioned navigation), common.py (data access, caching, palette), views/
scripts/            generate_data.py, run_detection.py
tests/              130 tests, fully offline
```

## Tests

`pytest` runs 130 tests in about 30 seconds, with no network access (the
NSL-KDD tests use tiny synthetic frames in the dataset's schema). They cover:

- every rule's positive and negative case and the Sigma modifiers;
- correlation's transitivity, window, escalation, and titles;
- evaluation metrics on hand-built ground truth;
- each hunting guard (writes, ATTACH, PRAGMA, stacked statements, timeouts,
  hidden ground truth);
- storage, including migrating a v1 database file;
- the generator's kill-chain structure;
- an end-to-end pipeline run on two seeds;
- PowerShell decoding, IOC extraction, playbook rendering and per-technique
  scoping, report escaping, and case-note storage;
- tuning sweeps (recall never rises as a threshold tightens), the alert-budget
  curve, the streaming simulator's dedupe and hour-close timing, and the
  Navigator layer's scores;
- the search language (terms, pipelines, the OTHER fold, hidden ground
  truth, eight kinds of malformed query), attack-graph direction and layout,
  feed sightings and retro-hunts, domain scoring, the watchlist, and
  suppression end to end (suppressed alerts stay out of incidents and
  evaluation).

The regression tests for the rule-engine bugs above were mutation-checked:
re-introducing each bug makes exactly its test fail.

To reproduce the 20-seed figures:

```python
from datetime import datetime
from socdash import pipeline, evaluation
from socdash.storage import db
from socdash.detection import rule_engine

for seed in range(1, 21):
    path = f"/tmp/seed{seed}.db"
    pipeline.run_pipeline(db_path=path, scenario_count=14, campaign_count=2, seed=seed, end=datetime(2026, 9, 6))
    conn = db.connect(path)
    ev = evaluation.evaluate(db.read_events(conn), db.read_alerts(conn), rule_engine.load_rules())
    print(seed, ev["techniques"][["scenario_tag", "recall"]].values.tolist(), ev["campaigns"]["reconstructed"].tolist())
```
