#!/usr/bin/env python3
"""Telemetry report generator for Bio Siege logs.

Parses JSONL telemetry files and produces:
- battles.csv: Detailed tabular breakdown of all battles.
- summary.txt: Human-readable aggregated session & battle statistics.
"""

import argparse
import csv
import json
import os
import sys
import statistics
from typing import Any, Dict, List, Optional, Tuple


def parse_telemetry_files(file_paths: List[str]) -> List[Dict[str, Any]]:
    """Reads JSONL logs. Every event gets `_tester` (the name of the log's folder: one folder per tester),
    `_file` and `_session` (the index of the session_start it follows in that file), used by the Living Base
    section of the summary."""
    events: List[Dict[str, Any]] = []
    for path in file_paths:
        if not os.path.exists(path):
            continue
        tester = os.path.basename(os.path.dirname(os.path.abspath(path)))
        session_index = 0
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                    if isinstance(event, dict):
                        if event.get("event") == "session_start":
                            session_index += 1
                        event["_tester"] = tester
                        event["_file"] = path
                        event["_session"] = session_index
                        events.append(event)
                except Exception:
                    # Gracefully skip truncated or invalid lines
                    continue
    return events


def flags_key_of(launch: Optional[Dict[str, Any]]) -> str:
    """Sorted names of the flags that are true in the launch event, joined with '+', or 'none'."""
    flags = launch.get("flags") if launch else None
    if not isinstance(flags, dict):
        return "none"
    on = sorted(str(k) for k, v in flags.items() if v is True)
    return "+".join(on) if on else "none"


def largest_strain_share_of(launch: Optional[Dict[str, Any]]) -> Any:
    """Largest army_atp_by_type value over their sum, rounded to 3 decimals, or '' when missing."""
    by_type = launch.get("army_atp_by_type") if launch else None
    if not isinstance(by_type, dict) or not by_type:
        return ""
    try:
        values = [float(v) for v in by_type.values()]
    except (TypeError, ValueError):
        return ""
    total = sum(values)
    if total <= 0:
        return ""
    return round(max(values) / total, 3)


def defense_share_of(launch: Optional[Dict[str, Any]]) -> Any:
    """base_atp / (base_atp + army_atp + unspent_atp), or '' when missing."""
    if not launch:
        return ""
    try:
        base = float(launch["base_atp"])
        army = float(launch["army_atp"])
        unspent = float(launch["unspent_atp"])
    except (KeyError, TypeError, ValueError):
        return ""
    total = base + army + unspent
    if total <= 0:
        return ""
    return round(base / total, 3)


def extract_battles(events: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    battles: List[Dict[str, Any]] = []
    current_launch: Optional[Dict[str, Any]] = None
    battle_index = 0

    for ev in events:
        ev_name = ev.get("event")
        if ev_name == "launch":
            current_launch = ev
        elif ev_name == "battle_end":
            battle_index += 1
            battle_row: Dict[str, Any] = {
                "battle_index": battle_index,
                "outcome": ev.get("outcome", ""),
                "end_reason": ev.get("end_reason", ""),
                "battle_s": ev.get("battle_s", 0.0),
                "ticks": ev.get("ticks", 0),
                "seed": current_launch.get("seed", "") if current_launch else "",
                "base_atp": current_launch.get("base_atp", "") if current_launch else "",
                "army_atp": current_launch.get("army_atp", "") if current_launch else "",
                "unspent_atp": current_launch.get("unspent_atp", "") if current_launch else "",
                "nucleus_hp": ev.get("nucleus_hp", 0),
                "nucleus_max_hp": ev.get("nucleus_max_hp", 0),
                "structures_destroyed": ev.get("structures_destroyed", 0),
                "structures_total": ev.get("structures_total", 0),
                "pathogens_killed": ev.get("pathogens_killed", 0),
                "pathogens_total": ev.get("pathogens_total", 0),
                "first_contact_s": ev.get("first_contact_s", -1.0),
                "first_destroyed_structure_type": ev.get("first_destroyed_structure_type", ""),
                "prediction_structure_id": ev.get("prediction_structure_id", ""),
                "prediction_correct": ev.get("prediction_correct", ""),
                "flags_key": flags_key_of(current_launch),
                "largest_strain_share": largest_strain_share_of(current_launch),
                "defense_share": defense_share_of(current_launch),
                "score": ev.get("score", ""),
            }
            battles.append(battle_row)
            current_launch = None
    return battles


def _is_number(v: Any) -> bool:
    if isinstance(v, bool) or v is None or str(v).strip() == "":
        return False
    try:
        float(v)
    except (TypeError, ValueError):
        return False
    return True


def _prediction_outcomes(battles: List[Dict[str, Any]]) -> List[bool]:
    return [
        b["prediction_correct"] is True or str(b["prediction_correct"]).lower() == "true"
        for b in battles
        if b.get("prediction_correct") is not None
        and str(b.get("prediction_correct")).strip() != ""
    ]


def identity_metrics_lines(battles: List[Dict[str, Any]]) -> List[str]:
    """The 'Identity metrics' summary section, one block per flags_key.

    Outbreak mode was removed (#149); old logs with outbreak_* events are still read, and those events are ignored.
    """
    lines: List[str] = ["", "Identity metrics (by flag set):"]
    keys = sorted({str(b.get("flags_key", "none")) for b in battles})
    if not keys:
        lines.append("  (no battles)")
        return lines
    for key in keys:
        group = [b for b in battles if str(b.get("flags_key", "none")) == key]
        shares = [float(b["largest_strain_share"]) for b in group if _is_number(b.get("largest_strain_share"))]
        defs = [float(b["defense_share"]) for b in group if _is_number(b.get("defense_share"))]
        scores = [float(b["score"]) for b in group if _is_number(b.get("score"))]
        preds = _prediction_outcomes(group)
        lines.append(f"  [{key}]")
        lines.append(f"    battles: {len(group)}")
        lines.append(
            f"    median largest strain share: {statistics.median(shares):.3f}" if shares
            else "    median largest strain share: n/a"
        )
        lines.append(
            f"    battles with defense_share > 0.20: {sum(1 for d in defs if d > 0.20) / len(defs) * 100:.1f}%"
            if defs else "    battles with defense_share > 0.20: n/a"
        )
        lines.append(f"    median score: {statistics.median(scores):g}" if scores else "    median score: n/a")
        correct = sum(1 for p in preds if p)
        lines.append(
            f"    prediction accuracy: {correct}/{len(preds)} ({correct / len(preds) * 100:.1f}%)" if preds
            else "    prediction accuracy: n/a"
        )
    return lines


def _num(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def living_base_sessions(events: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """One record per session that logged any lb_* event: tester, unix start (or None), length in seconds."""
    groups: Dict[Tuple[Any, Any, Any], List[Dict[str, Any]]] = {}
    for ev in events:
        key = (ev.get("_tester", ""), ev.get("_file", ""), ev.get("_session", 0))
        groups.setdefault(key, []).append(ev)
    sessions: List[Dict[str, Any]] = []
    for (tester, _file, _idx), evs in groups.items():
        if not any(str(e.get("event", "")).startswith("lb_") for e in evs):
            continue
        start = next((e for e in evs if e.get("event") == "session_start"), None)
        unix = start.get("unix_s") if start else None
        times = [_num(e.get("t_ms")) for e in evs if "t_ms" in e]
        length_s = (max(times) - min(times)) / 1000.0 if times else 0.0
        sessions.append({
            "tester": tester,
            "unix": float(unix) if _is_number(unix) else None,
            "length_s": length_s,
            "events": evs,
        })
    return sessions


def living_base_metrics(events: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """The Phase 2 gate numbers (plan section 14), or None when the logs hold no Living Base events."""
    sessions = living_base_sessions(events)
    if not sessions:
        return None
    metrics: Dict[str, Any] = {"sessions": len(sessions)}

    # Sessions per tester per day: the mean over every (tester, UTC day) that has a session.
    per_day: Dict[Tuple[Any, int], int] = {}
    for s in sessions:
        if s["unix"] is not None:
            day = int(s["unix"] // 86400)
            per_day[(s["tester"], day)] = per_day.get((s["tester"], day), 0) + 1
    metrics["sessions_per_tester_day"] = (
        sum(per_day.values()) / len(per_day) if per_day else None
    )
    metrics["median_session_s"] = statistics.median([s["length_s"] for s in sessions])

    # Return within 24 h: a session is followed by another of the same tester starting within a day.
    timed = [s for s in sessions if s["unix"] is not None]
    returned = 0
    for s in timed:
        later = [
            o["unix"] - s["unix"]
            for o in timed
            if o["tester"] == s["tester"] and o["unix"] > s["unix"]
        ]
        if later and min(later) <= 86400:
            returned += 1
    metrics["return_24h"] = returned / len(timed) if timed else None

    raid_ends = [e for s in sessions for e in s["events"] if e.get("event") == "lb_raid_end"]
    metrics["raids_per_session"] = len(raid_ends) / len(sessions)

    # Army change between consecutive raids on the same opponent (identity proposal section 8).
    last_army: Dict[Tuple[Any, Any], Any] = {}
    pairs = 0
    changed = 0
    for e in raid_ends:
        key = (e.get("_tester", ""), e.get("opponent_id", ""))
        army = e.get("army_counts")
        if key in last_army:
            pairs += 1
            if army != last_army[key]:
                changed += 1
        last_army[key] = army
    metrics["army_change_rate"] = changed / pairs if pairs else None
    metrics["army_change_pairs"] = pairs

    all_events = [e for s in sessions for e in s["events"]]
    earned = sum(_num(e.get("amino")) for e in all_events if e.get("event") == "lb_raid_end")
    earned += sum(_num(e.get("amino_gained")) for e in all_events if e.get("event") == "lb_defense_end")
    upgrades = [e for e in all_events if e.get("event") == "lb_upgrade"]
    metrics["amino_earned"] = earned
    metrics["amino_spent"] = sum(_num(e.get("cost")) for e in upgrades)
    picks: Dict[str, int] = {}
    for e in upgrades:
        picks[str(e.get("id", "?"))] = picks.get(str(e.get("id", "?")), 0) + 1
    metrics["upgrade_picks"] = picks

    offline = [e for e in all_events if e.get("event") == "lb_defense_end" and e.get("live") is not True]
    replays = [e for e in all_events if e.get("event") == "lb_replay_watched"]
    metrics["offline_raids"] = len(offline)
    metrics["replays_watched"] = len(replays)
    metrics["replays_per_offline_raid"] = len(replays) / len(offline) if offline else None
    return metrics


def living_base_lines(events: List[Dict[str, Any]]) -> List[str]:
    """The 'Living Base' summary section. Empty when there are no Living Base events."""
    m = living_base_metrics(events)
    if m is None:
        return []

    def pct(v: Optional[float]) -> str:
        return f"{v * 100:.1f}%" if v is not None else "n/a"

    def num(v: Optional[float], digits: int = 2) -> str:
        return f"{v:.{digits}f}" if v is not None else "n/a"

    picks = ", ".join(f"{k} x{v}" for k, v in sorted(m["upgrade_picks"].items())) or "none"
    return [
        "",
        "Living Base:",
        f"  sessions: {m['sessions']}",
        f"  sessions per tester per day: {num(m['sessions_per_tester_day'])}",
        f"  median session length: {m['median_session_s']:.1f} s",
        f"  sessions that return within 24 h: {pct(m['return_24h'])}",
        f"  raids per session: {num(m['raids_per_session'])}",
        f"  army change rate between consecutive raids on the same opponent: {pct(m['army_change_rate'])} ({m['army_change_pairs']} pairs)",
        f"  Amino Acids earned: {m['amino_earned']:g}, spent: {m['amino_spent']:g}",
        f"  upgrade picks: {picks}",
        f"  replays watched per offline raid: {num(m['replays_per_offline_raid'])} ({m['replays_watched']} replays, {m['offline_raids']} offline raids)",
    ]


def generate_report(events: List[Dict[str, Any]], out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    battles = extract_battles(events)

    # 1. Write battles.csv
    csv_fields = [
        "battle_index",
        "outcome",
        "end_reason",
        "battle_s",
        "ticks",
        "seed",
        "base_atp",
        "army_atp",
        "unspent_atp",
        "nucleus_hp",
        "nucleus_max_hp",
        "structures_destroyed",
        "structures_total",
        "pathogens_killed",
        "pathogens_total",
        "first_contact_s",
        "first_destroyed_structure_type",
        "prediction_structure_id",
        "prediction_correct",
        "flags_key",
        "largest_strain_share",
        "defense_share",
        "score",
    ]

    csv_path = os.path.join(out_dir, "battles.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=csv_fields)
        writer.writeheader()
        for b in battles:
            writer.writerow(b)

    # 2. Write summary.txt
    summary_path = os.path.join(out_dir, "summary.txt")

    sessions_count = sum(1 for e in events if e.get("event") == "session_start")
    total_battles = len(battles)
    attacker_wins = sum(1 for b in battles if b.get("outcome") == "attacker")
    defender_wins = sum(1 for b in battles if b.get("outcome") == "defender")

    end_reasons: Dict[str, int] = {}
    for b in battles:
        reason = str(b.get("end_reason", "unknown"))
        end_reasons[reason] = end_reasons.get(reason, 0) + 1

    avg_battle_s = (
        sum(float(b.get("battle_s", 0.0)) for b in battles) / total_battles
        if total_battles > 0
        else 0.0
    )

    avg_structs_dest = (
        sum(int(b.get("structures_destroyed", 0)) for b in battles) / total_battles
        if total_battles > 0
        else 0.0
    )

    avg_pathogens_killed = (
        sum(int(b.get("pathogens_killed", 0)) for b in battles) / total_battles
        if total_battles > 0
        else 0.0
    )

    predictions = [
        b["prediction_correct"]
        for b in battles
        if b.get("prediction_correct") is not None
        and str(b.get("prediction_correct")).strip() != ""
    ]
    correct_preds = sum(1 for p in predictions if p is True or str(p).lower() == "true")

    # A survey event carries one question's answer (pivot, predictability, economy or map_feel), but older
    # logs put all four keys in one event. Averages run over the events that actually carry each key.
    surveys = [e for e in events if e.get("event") == "survey"]
    skipped_surveys = [e for e in events if e.get("event") == "survey_skipped"]

    def avg_of(key: str) -> Tuple[float, int]:
        values = [float(s[key]) for s in surveys if key in s]
        return (sum(values) / len(values) if values else 0.0), len(values)

    avg_pivot, n_pivot = avg_of("pivot")
    avg_pred, n_pred = avg_of("predictability")
    avg_econ, n_econ = avg_of("economy")
    map_feels: Dict[str, int] = {}
    for s in surveys:
        if "map_feel" in s:
            mf = str(s["map_feel"])
            map_feels[mf] = map_feels.get(mf, 0) + 1

    lines = [
        "=== Bio Siege Telemetry Summary ===",
        f"Total Sessions: {sessions_count}",
        f"Total Battles: {total_battles}",
        f"Attacker Wins: {attacker_wins} ({attacker_wins / total_battles * 100:.1f}%)" if total_battles > 0 else "Attacker Wins: 0 (0.0%)",
        f"Defender Wins: {defender_wins} ({defender_wins / total_battles * 100:.1f}%)" if total_battles > 0 else "Defender Wins: 0 (0.0%)",
        "",
        "End Reasons Breakdown:",
    ]
    for reason, count in sorted(end_reasons.items()):
        lines.append(f"  - {reason}: {count}")

    lines.extend([
        "",
        f"Average Battle Duration: {avg_battle_s:.1f} s",
        f"Average Structures Destroyed: {avg_structs_dest:.1f}",
        f"Average Pathogens Killed: {avg_pathogens_killed:.1f}",
        "",
        f"Predictions Made: {len(predictions)}",
        f"Predictions Correct: {correct_preds} ({correct_preds / len(predictions) * 100:.1f}%)" if predictions else "Predictions Correct: 0 (0.0%)",
        "",
        f"Surveys Submitted: {len(surveys)}",
        f"Surveys Skipped: {len(skipped_surveys)}",
    ])
    if surveys:
        lines.extend([
            f"  - Avg Pivot Rating: {avg_pivot:.2f} / 5 ({n_pivot} answers)",
            f"  - Avg Predictability: {avg_pred:.2f} / 5 ({n_pred} answers)",
            f"  - Avg Economy Rating: {avg_econ:.2f} / 5 ({n_econ} answers)",
            f"  - Map Feel Breakdown: {map_feels}",
        ])

    lines.extend(identity_metrics_lines(battles))
    lines.extend(living_base_lines(events))

    with open(summary_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate telemetry report from JSONL logs.")
    parser.add_argument("log_files", nargs="+", help="Path(s) to JSONL log file(s)")
    parser.add_argument("--out", "-o", default="report", help="Output directory for report files")
    args = parser.parse_args()

    events = parse_telemetry_files(args.log_files)
    generate_report(events, args.out)
    print(f"Report generated successfully in: {args.out}")


if __name__ == "__main__":
    main()
