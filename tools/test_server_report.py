#!/usr/bin/env python3
"""Tests for tools/server_report.py. Run as `python tools/test_server_report.py` or
`python -m unittest tools.test_server_report` from the repository root."""

import contextlib
import io
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import server_report as sr  # noqa: E402

FIXTURE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "server_report.json")


def _load():
    with open(FIXTURE, "r", encoding="utf-8") as f:
        return json.load(f)["report"]


class TestServerReport(unittest.TestCase):
    def setUp(self):
        self.report = _load()
        self.days = self.report["days"]

    def test_strain_rows_give_share_and_win_rate(self):
        rows = {r["strain"]: r for r in sr.strain_rows(self.days)}
        wild = rows["rhinovirus/wild"]
        self.assertEqual(wild["used_raids"], 18)
        self.assertAlmostEqual(wild["share_pct"], 100.0 * 18 / 30)
        self.assertAlmostEqual(wild["win_rate_pct"], 100.0 * 8 / 18)
        hard = rows["rhinovirus/capsid_hardening"]
        self.assertEqual(hard["used_raids"], 12)
        self.assertAlmostEqual(hard["win_rate_pct"], 100.0 * 10 / 12)
        self.assertEqual(hard["used_atp"], 480)

    def test_strain_rows_are_sorted_by_use_then_name(self):
        names = [r["strain"] for r in sr.strain_rows(self.days)]
        self.assertEqual(names[0], "rhinovirus/wild")
        self.assertEqual(names[1], "rhinovirus/capsid_hardening")
        self.assertEqual(names[-1], "bacteriophage/rapid_replication")

    def test_usage_trend_covers_the_top_three_over_every_day(self):
        trend = sr.usage_trend(self.days)
        self.assertEqual(list(trend.keys()), ["rhinovirus/wild", "rhinovirus/capsid_hardening", "staphylococcus/wild"])
        wild = dict(trend["rhinovirus/wild"])
        self.assertAlmostEqual(wild["2026-10-01"], 80.0)
        self.assertAlmostEqual(wild["2026-10-02"], 50.0)
        self.assertEqual(wild["2026-10-03"], 0.0, "a day without raids is 0, not a crash")
        self.assertEqual(len(trend["staphylococcus/wild"]), 3)

    def test_retention_lines(self):
        lines = sr.retention_lines(self.report["retention"])
        self.assertEqual(lines[0], "D1 retention: 60.0% (6 of 10 players)")
        self.assertEqual(lines[1], "D7 retention: 25.0% (1 of 4 players)")
        self.assertIn("n/a", sr.retention_lines({})[0])

    def test_raids_per_active_user(self):
        rows = sr.raids_per_active_user(self.days)
        self.assertEqual(rows[0], ("2026-10-01", 10, 5, 2.0))
        self.assertEqual(rows[1], ("2026-10-02", 20, 8, 2.5))
        self.assertEqual(rows[2], ("2026-10-03", 0, 0, 0.0))

    def test_the_report_has_every_section(self):
        text = sr.format_report(self.report, 1)
        for needle in (
            "Bio Siege server report, 2026-10-01 to 2026-10-03",
            "Strain usage share vs win rate",
            "rhinovirus/wild",
            "Usage share trend, top 3 strains",
            "D1 retention: 60.0%",
            "D7 retention: 25.0%",
            "Raids per active user per day",
            "2026-10-02: 20 raids / 8 active = 2.50",
            "Flagged players (receptor hit rate): 1",
        ):
            self.assertIn(needle, text)

    def test_an_empty_range_does_not_crash(self):
        text = sr.format_report({"days": [], "retention": {}, "players": 0})
        self.assertIn("no raids with strain data", text)
        self.assertIn("Flagged players (receptor hit rate): 0", text)

    def test_the_fixture_cli_prints_the_report(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = sr.main(["--fixture", FIXTURE])
        self.assertEqual(code, 0)
        self.assertIn("Flagged players (receptor hit rate): 1", out.getvalue())

    def test_missing_configuration_is_a_clear_error(self):
        saved = {k: os.environ.pop(k, None) for k in (sr.URL_ENV, sr.KEY_ENV)}
        try:
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                code = sr.main([])
            self.assertEqual(code, 2)
            self.assertIn(sr.URL_ENV, err.getvalue())
        finally:
            for k, v in saved.items():
                if v is not None:
                    os.environ[k] = v

    def test_the_key_is_never_printed_and_comes_only_from_the_environment(self):
        with open(os.path.join(os.path.dirname(FIXTURE), "..", "server_report.py"), encoding="utf-8") as f:
            source = f.read()
        self.assertNotIn("--http-key", source)
        self.assertIn("os.environ.get(KEY_ENV", source)


if __name__ == "__main__":
    unittest.main()
