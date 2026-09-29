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


if __name__ == "__main__":
    unittest.main()
