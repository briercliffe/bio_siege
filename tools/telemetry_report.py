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
from typing import Any, Dict, List, Optional


def parse_telemetry_files(file_paths: List[str]) -> List[Dict[str, Any]]:
    events: List[Dict[str, Any]] = []
    for path in file_paths:
        if not os.path.exists(path):
            continue
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                    if isinstance(event, dict):
                        events.append(event)
                except Exception:
                    # Gracefully skip truncated or invalid lines
                    continue
    return events


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
            }
            battles.append(battle_row)
            current_launch = None
    return battles


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

    surveys = [e for e in events if e.get("event") == "survey"]
    avg_pivot = (
        sum(float(s.get("pivot", 0)) for s in surveys) / len(surveys)
        if surveys
        else 0.0
    )
    avg_pred = (
        sum(float(s.get("predictability", 0)) for s in surveys) / len(surveys)
        if surveys
        else 0.0
    )
    avg_econ = (
        sum(float(s.get("economy", 0)) for s in surveys) / len(surveys)
        if surveys
        else 0.0
    )
    map_feels: Dict[str, int] = {}
    for s in surveys:
        mf = str(s.get("map_feel", "unknown"))
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
    ])
    if surveys:
        lines.extend([
            f"  - Avg Pivot Rating: {avg_pivot:.2f} / 5",
            f"  - Avg Predictability: {avg_pred:.2f} / 5",
            f"  - Avg Economy Rating: {avg_econ:.2f} / 5",
            f"  - Map Feel Breakdown: {map_feels}",
        ])

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
