#!/usr/bin/env python3
import csv
import os
import shutil
import tempfile
import unittest

from tools.telemetry_report import parse_telemetry_files, extract_battles, generate_report


class TestTelemetryReport(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.fixture_path = os.path.join(
            os.path.dirname(__file__), "fixtures", "sample_telemetry.jsonl"
        )

    def tearDown(self):
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)

    def test_parse_telemetry_fixture_handles_truncated_lines(self):
        self.assertTrue(os.path.exists(self.fixture_path), "Fixture must exist")
        events = parse_telemetry_files([self.fixture_path])
        # The fixture contains 23 valid lines and 1 truncated line at the end
        self.assertGreater(len(events), 0)
        # Verify that all parsed items are dicts with an "event" key
        for ev in events:
            self.assertIn("event", ev)

    def test_extract_battles_contains_win_and_loss(self):
        events = parse_telemetry_files([self.fixture_path])
        battles = extract_battles(events)
        self.assertEqual(len(battles), 2, "Expected exactly 2 completed battles")

        win_battle = battles[0]
        self.assertEqual(win_battle["outcome"], "attacker")
        self.assertEqual(win_battle["end_reason"], "nucleus_destroyed")
        self.assertEqual(win_battle["seed"], 1001)
        self.assertEqual(win_battle["base_atp"], 120)
        self.assertEqual(win_battle["prediction_correct"], True)

        loss_battle = battles[1]
        self.assertEqual(loss_battle["outcome"], "defender")
        self.assertEqual(loss_battle["end_reason"], "all_pathogens_dead")
        self.assertEqual(loss_battle["seed"], 1002)
        self.assertEqual(loss_battle["prediction_correct"], False)

    def test_generate_report_creates_csv_and_summary(self):
        events = parse_telemetry_files([self.fixture_path])
        generate_report(events, self.temp_dir)

        csv_path = os.path.join(self.temp_dir, "battles.csv")
        summary_path = os.path.join(self.temp_dir, "summary.txt")

        self.assertTrue(os.path.exists(csv_path), "battles.csv must be created")
        self.assertTrue(os.path.exists(summary_path), "summary.txt must be created")

        # Verify CSV contents
        with open(csv_path, "r", encoding="utf-8") as f:
            reader = list(csv.DictReader(f))
            self.assertEqual(len(reader), 2)
            self.assertEqual(reader[0]["outcome"], "attacker")
            self.assertEqual(reader[1]["outcome"], "defender")
            self.assertEqual(reader[0]["first_destroyed_structure_type"], "macrophage")

        # Verify Summary contents
        with open(summary_path, "r", encoding="utf-8") as f:
            text = f.read()
            self.assertIn("Total Battles: 2", text)
            self.assertIn("Attacker Wins: 1", text)
            self.assertIn("Defender Wins: 1", text)
            self.assertIn("nucleus_destroyed: 1", text)
            self.assertIn("all_pathogens_dead: 1", text)
            self.assertIn("Predictions Made: 2", text)
            self.assertIn("Predictions Correct: 1", text)
            self.assertIn("Surveys Submitted: 1", text)


class TestSurveyEvents(unittest.TestCase):
    """The Results screen logs one question per survey event (and survey_skipped when skipped)."""

    def test_one_key_per_event_and_skips(self):
        events = [
            {"t_ms": 1, "event": "survey", "pivot": 4, "question": "pivot"},
            {"t_ms": 2, "event": "survey", "pivot": 2, "question": "pivot"},
            {"t_ms": 3, "event": "survey", "map_feel": "just_right", "question": "map_feel"},
            {"t_ms": 4, "event": "survey", "economy": 5, "question": "economy"},
            {"t_ms": 5, "event": "survey_skipped", "question": "predictability"},
        ]
        out_dir = tempfile.mkdtemp()
        try:
            generate_report(events, out_dir)
            with open(os.path.join(out_dir, "summary.txt"), "r", encoding="utf-8") as f:
                text = f.read()
        finally:
            shutil.rmtree(out_dir, ignore_errors=True)
        self.assertIn("Surveys Submitted: 4", text)
        self.assertIn("Surveys Skipped: 1", text)
        self.assertIn("Avg Pivot Rating: 3.00 / 5 (2 answers)", text)
        self.assertIn("Avg Predictability: 0.00 / 5 (0 answers)", text)
        self.assertIn("Avg Economy Rating: 5.00 / 5 (1 answers)", text)
        self.assertIn("{'just_right': 1}", text)


class TestIdentityMetrics(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.identity_path = os.path.join(
            os.path.dirname(__file__), "fixtures", "identity_telemetry.jsonl"
        )
        self.old_path = os.path.join(
            os.path.dirname(__file__), "fixtures", "sample_telemetry.jsonl"
        )

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_largest_strain_share_and_flags_key(self):
        battles = extract_battles(parse_telemetry_files([self.identity_path]))
        self.assertEqual(len(battles), 3)
        self.assertEqual(battles[0]["largest_strain_share"], 0.75)
        self.assertEqual(battles[0]["flags_key"], "none")
        self.assertEqual(battles[0]["defense_share"], 0.25)
        self.assertEqual(battles[0]["score"], "")
        self.assertEqual(battles[1]["flags_key"], "bcell_analysis+immune_memory")
        self.assertEqual(battles[1]["largest_strain_share"], 0.5)
        self.assertEqual(battles[1]["score"], 420)

    def test_summary_has_one_block_per_flag_set(self):
        generate_report(parse_telemetry_files([self.identity_path]), self.temp_dir)
        with open(os.path.join(self.temp_dir, "summary.txt"), "r", encoding="utf-8") as f:
            text = f.read()
        self.assertIn("Identity metrics", text)
        self.assertIn("[none]", text)
        self.assertIn("[bcell_analysis+immune_memory]", text)
        both_block, none_block = text.split("[bcell_analysis+immune_memory]")[1].split("[none]")
        self.assertIn("battles: 1", none_block)
        self.assertIn("battles: 2", both_block)
        self.assertIn("median score: 510", both_block)
        # The fixture still holds an old outbreak_run_end event (#149): it is read and ignored.
        self.assertNotIn("outbreak", text)
        self.assertIn("prediction accuracy: 1/2 (50.0%)", both_block)

    def test_old_logs_leave_new_columns_empty(self):
        generate_report(parse_telemetry_files([self.old_path]), self.temp_dir)
        with open(os.path.join(self.temp_dir, "battles.csv"), "r", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
        self.assertEqual(len(rows), 2)
        for row in rows:
            self.assertEqual(row["largest_strain_share"], "")
            self.assertEqual(row["score"], "")
            self.assertEqual(row["flags_key"], "none")


if __name__ == "__main__":
    unittest.main()
