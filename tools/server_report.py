#!/usr/bin/env python3
"""Meta report from the online server (AM-12, docs/SERVER_PLAN.md).

Calls the admin RPCs `admin_report` and `admin_flagged_list` with the server's http key and prints the evidence the
Phase 3 gate asks for:

- the strain usage share vs win rate table,
- the trend of the usage share of the top 3 strains over the days,
- D1 / D7 retention,
- raids per active user per day,
- the number of players flagged by the receptor-hit-rate rule.

    BIO_SIEGE_SERVER_URL=https://host:7350 BIO_SIEGE_HTTP_KEY=... python tools/server_report.py --days 14
    python tools/server_report.py --fixture tools/fixtures/server_report.json     # offline, no server

The key is read from the environment only (never a file or an argument), and nothing is sent anywhere but the server
you name.
"""

import argparse
import datetime
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional, Tuple

URL_ENV = "BIO_SIEGE_SERVER_URL"
KEY_ENV = "BIO_SIEGE_HTTP_KEY"
TOP_STRAINS = 3


def call_rpc(url: str, http_key: str, rpc_id: str, payload: Dict[str, Any], timeout: float = 30.0) -> Dict[str, Any]:
    """POST /v2/rpc/<id>?http_key=...&unwrap with a JSON body. Returns the parsed JSON object."""
    endpoint = "%s/v2/rpc/%s?%s" % (url.rstrip("/"), rpc_id, urllib.parse.urlencode({"http_key": http_key, "unwrap": ""}))
    request = urllib.request.Request(
        endpoint, data=json.dumps(payload).encode("utf-8"), headers={"Content-Type": "application/json"}, method="POST"
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = json.loads(response.read().decode("utf-8"))
    if not isinstance(body, dict) or not body.get("ok", False):
        raise RuntimeError("%s failed: %s" % (rpc_id, body.get("error", body) if isinstance(body, dict) else body))
    return body


def strain_rows(days: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """One row per strain key: raids it was used in, the share of all raids that used it, wins and the win rate when used."""
    total_raids = sum(int(d.get("raids", 0)) for d in days)
    used: Dict[str, int] = {}
    wins: Dict[str, int] = {}
    atp: Dict[str, int] = {}
    for d in days:
        for key, s in (d.get("strains") or {}).items():
            used[key] = used.get(key, 0) + int(s.get("used_raids", 0))
            wins[key] = wins.get(key, 0) + int(s.get("wins", 0))
            atp[key] = atp.get(key, 0) + int(s.get("used_atp", 0))
    rows = []
    for key in used:
        rows.append(
            {
                "strain": key,
                "used_raids": used[key],
                "share_pct": 100.0 * used[key] / total_raids if total_raids else 0.0,
                "wins": wins[key],
                "win_rate_pct": 100.0 * wins[key] / used[key] if used[key] else 0.0,
                "used_atp": atp[key],
            }
        )
    rows.sort(key=lambda r: (-r["used_raids"], r["strain"]))
    return rows


def usage_trend(days: List[Dict[str, Any]], top: int = TOP_STRAINS) -> Dict[str, List[Tuple[str, float]]]:
    """Usage share (percent of that day's raids) per day for the `top` most used strains over the whole range."""
    rows = strain_rows(days)[:top]
    trend: Dict[str, List[Tuple[str, float]]] = {}
    for row in rows:
        series = []
        for d in days:
            raids = int(d.get("raids", 0))
            used = int(((d.get("strains") or {}).get(row["strain"]) or {}).get("used_raids", 0))
            series.append((str(d.get("date", "")), 100.0 * used / raids if raids else 0.0))
        trend[row["strain"]] = series
    return trend


def retention_lines(retention: Dict[str, Any]) -> List[str]:
    lines = []
    for name, label in (("d1", "D1"), ("d7", "D7")):
        entry = retention.get(name) or {}
        eligible = int(entry.get("eligible", 0))
        retained = int(entry.get("retained", 0))
        if eligible:
            lines.append("%s retention: %.1f%% (%d of %d players)" % (label, 100.0 * retained / eligible, retained, eligible))
        else:
            lines.append("%s retention: n/a (no player is old enough yet)" % label)
    return lines


def raids_per_active_user(days: List[Dict[str, Any]]) -> List[Tuple[str, int, int, float]]:
    """(date, raids, active users, raids per active user) for each day."""
    out = []
    for d in days:
        raids = int(d.get("raids", 0))
        active = int(d.get("active_users", 0))
        out.append((str(d.get("date", "")), raids, active, raids / active if active else 0.0))
    return out


def format_report(report: Dict[str, Any], flagged_count: Optional[int] = None) -> str:
    days: List[Dict[str, Any]] = list(report.get("days") or [])
    lines: List[str] = []
    first = days[0].get("date", "?") if days else "?"
    last = days[-1].get("date", "?") if days else "?"
    total_raids = sum(int(d.get("raids", 0)) for d in days)
    wins = sum(int(d.get("attacker_wins", 0)) for d in days)
    lines.append("Bio Siege server report, %s to %s" % (first, last))
    lines.append(
        "Players: %d | raids in range: %d | attacker win rate: %s"
        % (int(report.get("players", 0)), total_raids, "%.1f%%" % (100.0 * wins / total_raids) if total_raids else "n/a")
    )
    lines.append("")

    lines.append("Strain usage share vs win rate")
    rows = strain_rows(days)
    if rows:
        width = max(len("strain"), max(len(r["strain"]) for r in rows))
        lines.append("  %-*s  %6s  %8s  %6s  %8s" % (width, "strain", "raids", "share", "wins", "win rate"))
        for r in rows:
            lines.append(
                "  %-*s  %6d  %7.1f%%  %6d  %7.1f%%" % (width, r["strain"], r["used_raids"], r["share_pct"], r["wins"], r["win_rate_pct"])
            )
    else:
        lines.append("  (no raids with strain data in this range)")
    lines.append("")

    lines.append("Usage share trend, top %d strains (percent of the day's raids)" % TOP_STRAINS)
    trend = usage_trend(days)
    if trend:
        for strain, series in trend.items():
            lines.append("  %s: %s" % (strain, "  ".join("%s %.0f%%" % (date[5:], pct) for date, pct in series)))
    else:
        lines.append("  (no data)")
    lines.append("")

    lines.append("Retention")
    for line in retention_lines(report.get("retention") or {}):
        lines.append("  " + line)
    lines.append("")

    lines.append("Raids per active user per day")
    for date, raids, active, ratio in raids_per_active_user(days):
        lines.append("  %s: %d raids / %d active = %.2f" % (date, raids, active, ratio))
    lines.append("")

    flagged = flagged_count if flagged_count is not None else int(report.get("flagged", 0))
    lines.append("Flagged players (receptor hit rate): %d" % flagged)
    return "\n".join(lines)


def load_fixture(path: str) -> Tuple[Dict[str, Any], Optional[int]]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    flagged = data.get("flagged_list")
    return data["report"], (len(flagged) if isinstance(flagged, list) else None)


def fetch_report(url: str, http_key: str, date_from: str, date_to: str) -> Tuple[Dict[str, Any], Optional[int]]:
    report = call_rpc(url, http_key, "admin_report", {"from": date_from, "to": date_to})
    flagged = call_rpc(url, http_key, "admin_flagged_list", {})
    return report, len(flagged.get("players") or [])


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Print the Bio Siege online meta report.")
    parser.add_argument("--days", type=int, default=14, help="how many days to look back (default 14)")
    parser.add_argument("--from", dest="date_from", help="first day, yyyy-mm-dd (overrides --days)")
    parser.add_argument("--to", dest="date_to", help="last day, yyyy-mm-dd (default today, UTC)")
    parser.add_argument("--fixture", help="read a saved report instead of calling a server")
    args = parser.parse_args(argv)

    if args.fixture:
        report, flagged = load_fixture(args.fixture)
    else:
        url = os.environ.get(URL_ENV, "")
        key = os.environ.get(KEY_ENV, "")
        if not url or not key:
            print("Set %s and %s (or use --fixture)." % (URL_ENV, KEY_ENV), file=sys.stderr)
            return 2
        today = datetime.datetime.now(datetime.timezone.utc).date()
        date_to = args.date_to or today.isoformat()
        date_from = args.date_from or (datetime.date.fromisoformat(date_to) - datetime.timedelta(days=max(args.days, 1) - 1)).isoformat()
        try:
            report, flagged = fetch_report(url, key, date_from, date_to)
        except (urllib.error.URLError, RuntimeError, OSError, ValueError) as e:
            print("Could not get the report: %s" % e, file=sys.stderr)
            return 1
    print(format_report(report, flagged))
    return 0


if __name__ == "__main__":
    sys.exit(main())
