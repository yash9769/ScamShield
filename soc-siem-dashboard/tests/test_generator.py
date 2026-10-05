from datetime import datetime

from socdash.generator import generate_dataset
from socdash.generator.entities import EXTERNAL_IPS, HOSTS, USERS

EXPECTED_COLUMNS = {
    "event_id", "ts", "event_type", "user", "host", "src_ip", "src_country",
    "dst_ip", "direction", "action", "outcome", "port", "protocol",
    "bytes_sent", "bytes_received", "process_name", "command_line", "domain",
    "scenario_tag", "scenario_id", "campaign_id",
}
SCENARIO_TYPES = {
    "brute_force", "port_scan", "impossible_travel", "data_exfiltration",
    "dns_beaconing", "suspicious_process", "lateral_movement",
}
KILL_CHAIN_ORDER = ["port_scan", "brute_force", "suspicious_process", "dns_beaconing", "lateral_movement", "data_exfiltration"]


def _dataset(**kwargs):
    defaults = dict(start=datetime(2026, 1, 1), end=datetime(2026, 1, 4), base_per_hour=15, scenario_count=6, campaign_count=1, seed=3)
    defaults.update(kwargs)
    return generate_dataset(**defaults)


def test_entity_pools_are_populated():
    assert len(HOSTS) >= 30
    assert len(USERS) >= 30
    assert len(EXTERNAL_IPS) >= 50
    assert any(ip.known_malicious for ip in EXTERNAL_IPS)
    assert any(not ip.known_malicious for ip in EXTERNAL_IPS)


def test_generate_dataset_schema():
    df = _dataset(end=datetime(2026, 1, 2), scenario_count=2, campaign_count=0, seed=1)
    assert EXPECTED_COLUMNS.issubset(df.columns)
    assert df["ts"].is_monotonic_increasing
    assert df["event_id"].is_unique


def test_generate_dataset_is_reproducible_with_same_seed():
    df1, df2 = _dataset(seed=7), _dataset(seed=7)
    assert len(df1) == len(df2)
    assert df1["event_type"].tolist() == df2["event_type"].tolist()
    assert df1["scenario_tag"].tolist() == df2["scenario_tag"].tolist()


def test_scenarios_inject_expected_tags():
    df = _dataset(end=datetime(2026, 1, 6), scenario_count=30)
    tags = set(df["scenario_tag"].dropna().unique())
    assert tags.issubset(SCENARIO_TYPES)
    assert len(tags) >= 5


def test_every_instance_has_exactly_one_technique():
    df = _dataset(scenario_count=12)
    tagged = df[df["scenario_id"].notna()]
    assert (tagged.groupby("scenario_id")["scenario_tag"].nunique() == 1).all()
    assert df.loc[df["scenario_tag"].notna(), "scenario_id"].notna().all()
    assert df.loc[df["scenario_tag"].isna(), "scenario_id"].isna().all()


def test_kill_chain_runs_six_stages_in_order_under_one_campaign():
    df = _dataset(scenario_count=0, campaign_count=1)
    campaign = df[df["campaign_id"].notna()]
    assert campaign["campaign_id"].nunique() == 1
    stages = campaign.groupby("scenario_id").agg(tag=("scenario_tag", "first"), start=("ts", "min")).sort_values("start")
    assert stages["tag"].tolist() == KILL_CHAIN_ORDER


def test_kill_chain_stages_share_the_intruders_footprint():
    df = _dataset(scenario_count=0, campaign_count=1)
    c = df[df["campaign_id"].notna()]
    scan_ips = set(c.loc[c["scenario_tag"] == "port_scan", "src_ip"])
    brute_ips = set(c.loc[c["scenario_tag"] == "brute_force", "src_ip"])
    exfil_ips = set(c.loc[c["scenario_tag"] == "data_exfiltration", "dst_ip"])
    assert scan_ips == brute_ips == exfil_ips, "one attacker address from scan to exfiltration"
    victim = set(c.loc[c["scenario_tag"] == "brute_force", "user"])
    assert victim == set(c.loc[c["scenario_tag"] == "suspicious_process", "user"]) == set(c.loc[c["scenario_tag"] == "lateral_movement", "user"])
    exfil_host = set(c.loc[c["scenario_tag"] == "data_exfiltration", "host"])
    assert exfil_host <= set(c.loc[c["scenario_tag"] == "lateral_movement", "host"]), "exfiltrates from a host it moved to"


def test_background_auth_has_one_country_per_user():
    """Regression test for the false-positive bug where a fresh random
    country per login made ordinary employees 'impossible-travel' against
    themselves. Pure background logins must never do that."""
    df = _dataset(end=datetime(2026, 1, 6), base_per_hour=25, scenario_count=0, campaign_count=0, seed=5)
    auth = df[(df["event_type"] == "auth") & df["user"].notna()]
    assert (auth.groupby("user")["src_country"].nunique() <= 1).all()


def test_only_injected_powershell_is_encoded():
    """Background PowerShell exists (admins run scripts) but is never
    encoded, so the suspicious-PowerShell rule's false-positive rate on the
    baseline is zero by construction, not by luck."""
    df = _dataset(end=datetime(2026, 1, 8), scenario_count=10)
    ps = df[(df["event_type"] == "process") & (df["process_name"] == "powershell.exe")]
    encoded = ps["command_line"].str.contains(" -enc ", regex=False)
    assert (~ps["scenario_tag"].isna() == encoded).all()
    assert (ps["scenario_tag"].isna()).any(), "the baseline should include benign PowerShell"
