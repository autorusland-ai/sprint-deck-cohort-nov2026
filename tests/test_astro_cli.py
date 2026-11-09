"""Offline regression tests; real Swiss Ephemeris/Bash checks skip if absent."""
import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import types
import unittest
from datetime import date, datetime, timedelta, timezone
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "deploy/scripts/astro-cli.py"


def load_cli(swe_module, name):
    spec = importlib.util.spec_from_file_location(name, CLI)
    module = importlib.util.module_from_spec(spec)
    with patch.dict(sys.modules, {"swisseph": swe_module}):
        spec.loader.exec_module(module)
    return module


def stub_swe():
    module = types.ModuleType("swisseph")
    for i, key in enumerate("SUN MOON MERCURY VENUS MARS JUPITER SATURN URANUS NEPTUNE PLUTO MEAN_NODE TRUE_NODE CHIRON".split()):
        setattr(module, key, i)
    module.FLG_MOSEPH = 4
    module.FLG_SPEED = 256
    module.Error = RuntimeError
    module.set_ephe_path = lambda _: None
    module.julday = lambda y, m, d, h: (y, m, d, h)
    module.time_equ = lambda _: 0.0
    module.calc_ut = lambda jd, planet, flags: ((0, 0, 0, -0.5, 0, 0), flags)
    module.houses = lambda *args: (tuple(range(0, 360, 30)), (0, 270))
    return module


SWE_STUB = stub_swe()
astro = load_cli(SWE_STUB, "astro_cli_stub")
try:
    import swisseph as real_swe
except ImportError:
    real_swe = None


class OfflineTests(unittest.TestCase):
    def test_all_includes_both_charts(self):
        with patch.object(sys, "argv", ["astro-cli.py", "all", "2026-06-01"]), \
             patch.object(astro, "show_natal") as natal, \
             patch.object(astro, "show_transits") as transits, \
             patch.object(astro, "show_bazi") as bazi, \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(astro.main(), 0)
        natal.assert_called_once_with()
        transits.assert_called_once_with(date(2026, 6, 1))
        bazi.assert_called_once_with(date(2026, 6, 1))

    def test_flags(self):
        self.assertEqual(astro.FLAGS, SWE_STUB.FLG_MOSEPH | SWE_STUB.FLG_SPEED)
        with patch.object(SWE_STUB, "calc_ut", wraps=SWE_STUB.calc_ut) as calc:
            self.assertEqual(astro.lon_of(123, SWE_STUB.MERCURY), (0, -0.5))
            calc.assert_called_once_with(123, SWE_STUB.MERCURY, astro.FLAGS)

    def test_coordinates(self):
        self.assertAlmostEqual(astro.BIRTH_LAT, 43.80)
        self.assertAlmostEqual(astro.BIRTH_LON, 131 + 59 / 60)

    def test_fmt_carry(self):
        self.assertEqual(astro.fmt(12 + 59.9 / 60), "13°00' Овна")
        self.assertEqual(astro.fmt(29 + 59.9 / 60), "0°00' Тельца")
        self.assertEqual(astro.fmt(359 + 59.9 / 60), "0°00' Овна")
        self.assertEqual(astro.fmt(-0.00001), "0°00' Овна")

    def test_daily_moment(self):
        dt = astro.moment(date(2026, 6, 1))
        self.assertEqual((dt.hour, dt.minute), (8, 0))
        self.assertEqual(astro.jd_of(dt), (2026, 6, 1, 5.0))
        self.assertIs(astro.moment(dt), dt)
        with self.assertRaises(ValueError):
            astro.moment(datetime(2026, 6, 1))

    def test_precise_solar_boundaries(self):
        before = datetime(2026, 2, 4, 8, tzinfo=astro.MSK)
        after = before + timedelta(seconds=1)
        with patch.object(astro, "sun_lon", return_value=314.999999):
            p_before = astro.pillars(before)
        with patch.object(astro, "sun_lon", return_value=315.0):
            p_after = astro.pillars(after)
        self.assertEqual((p_before[3], p_after[3]), (2025, 2026))
        self.assertEqual((p_before[1][1], p_after[1][1]), (1, 2))
        with patch.object(astro, "sun_lon", return_value=344.999999):
            self.assertEqual(astro.pillars(after)[1][1], 2)
        with patch.object(astro, "sun_lon", return_value=345):
            self.assertEqual(astro.pillars(after)[1][1], 3)

    def test_january_previous_year(self):
        for longitude in (280, 300, 314):
            with self.subTest(longitude=longitude), patch.object(astro, "sun_lon", return_value=longitude):
                self.assertEqual(astro.pillars(date(2026, 1, 15))[3], 2025)

    def test_month_five_tigers(self):
        for year in range(2020, 2030):
            for index in range(12):
                longitude = (315 + index * 30) % 360
                with patch.object(astro, "sun_lon", return_value=longitude):
                    yp, mp, _, _ = astro.pillars(date(year, 6, 1))
                self.assertEqual(mp, ((2 * (yp[0] % 5) + 2 + index) % 10,
                                      astro.MONTH_BRANCH_ORDER[index]))

    def test_day_anchor_unchanged(self):
        with patch.object(astro, "sun_lon", return_value=280):
            self.assertEqual(astro.pillars(date(2000, 1, 1))[2], (4, 6))
            self.assertEqual(astro.pillars(date(2000, 1, 2))[2], (5, 7))

    def test_birth_moment_not_noon(self):
        with patch.object(astro, "sun_lon", return_value=44) as sun:
            astro.pillars(astro.BIRTH_UTC)
            sun.assert_called_once_with(astro.jd_of(astro.BIRTH_UTC))

    def test_true_solar_hour(self):
        with patch.object(SWE_STUB, "time_equ", return_value=3.25 / 1440) as eot:
            hs, hb, solar = astro.natal_hour(6)
        eot.assert_called_once_with(astro.jd_of(astro.BIRTH_UTC))
        expected = astro.BIRTH_UTC + timedelta(minutes=3.25 + 4 * (astro.BIRTH_LON - 150))
        self.assertEqual(solar, expected)
        self.assertEqual((hs, hb), (0, 8))

    def test_ten_gods_geng_all_ten(self):
        expected = "偏财 正财 七杀 正官 偏印 正印 比肩 劫财 食神 伤官".split()
        self.assertEqual([astro.ten_god(6, s) for s in range(10)], expected)

    def test_houses_wrap_and_exact_cusp(self):
        cusps = tuple((350 + i * 30) % 360 for i in range(12))
        self.assertEqual(astro.house_of(350, cusps), 1)
        self.assertEqual(astro.house_of(0, cusps), 1)
        self.assertEqual(astro.house_of(20, cusps), 2)
        self.assertEqual(astro.house_of(349.99, cusps), 12)
        with self.assertRaises(ValueError):
            astro.house_of(0, ())

    def test_chart_uses_placidus(self):
        with patch.object(SWE_STUB, "houses", wraps=SWE_STUB.houses) as houses:
            astro.chart(123)
        houses.assert_called_once_with(123, astro.BIRTH_LAT, astro.BIRTH_LON, b"P")

    def test_nodes_chiron_and_retro_output(self):
        def calculate(jd, pid, flags):
            if pid == SWE_STUB.CHIRON:
                raise SWE_STUB.Error("missing file")
            return ((pid, 0, 0, -0.5, 0, 0), flags)
        output = io.StringIO()
        with patch.object(SWE_STUB, "calc_ut", side_effect=calculate) as calc, contextlib.redirect_stdout(output):
            astro.show_chart(123)
        text = output.getvalue()
        self.assertIn("mean (средний)", text)
        self.assertIn("true (истинный)", text)
        self.assertIn("Хирон: недоступен", text)
        self.assertIn("ретро", text)
        self.assertIn("ASC", text)
        self.assertIn("MC", text)
        self.assertIn("Куспид 12", text)
        self.assertEqual({call.args[1] for call in calc.call_args_list}, set(range(13)))

    def test_chiron_available(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            astro.show_chart(123)
        self.assertIn("Хирон:", output.getvalue())
        self.assertNotIn("недоступен", output.getvalue())

    def test_weak_aspects(self):
        natal = [("n", 0, 0)]
        strong = astro.aspect_lines([("t", 3, 0)], natal)
        weak = astro.aspect_lines([("t", 3.01, 0)], natal)
        self.assertTrue(strong)
        self.assertNotIn("слабый сигнал", strong[0])
        self.assertIn("слабый сигнал", weak[0])

    def test_transits_use_only_natal_cusps(self):
        output = io.StringIO()
        with patch.object(SWE_STUB, "houses", wraps=SWE_STUB.houses) as houses, \
             contextlib.redirect_stdout(output):
            astro.show_transits(date(2026, 11, 8))
        houses.assert_called_once_with(astro.jd_of(astro.BIRTH_UTC), astro.BIRTH_LAT,
                                       astro.BIRTH_LON, b"P")
        text = output.getvalue()
        self.assertIn("НАТАЛЬНЫЕ куспиды", text)
        self.assertNotIn("ASC", text)
        self.assertNotIn("MC", text)
        self.assertIn("ДОПОЛНИТЕЛЬНЫЕ АСПЕКТЫ", text)
        self.assertIn("true — только справочные координаты", text)

    def test_extra_targets_mean_only_and_chiron_availability(self):
        targets = astro.extra_aspect_targets(123)
        self.assertEqual(len(targets), 2)
        self.assertIn("mean", targets[0][0])
        self.assertIn("Хирон", targets[1][0])
        def calculate(jd, pid, flags):
            if pid == SWE_STUB.CHIRON:
                raise SWE_STUB.Error("missing file")
            self.assertEqual(pid, SWE_STUB.MEAN_NODE)
            return ((0, 0, 0, 0, 0, 0), flags)
        with patch.object(SWE_STUB, "calc_ut", side_effect=calculate):
            targets = astro.extra_aspect_targets(123)
        self.assertEqual(len(targets), 1)
        output = io.StringIO()
        with patch.object(SWE_STUB, "calc_ut", side_effect=lambda jd, pid, flags:
                          (_ for _ in ()).throw(SWE_STUB.Error("missing"))
                          if pid == SWE_STUB.CHIRON else ((0, 0, 0, 0, 0, 0), flags)), \
             contextlib.redirect_stdout(output):
            astro.show_transits(date(2026, 11, 8))
        self.assertIn("Аспекты к натальному Хирону недоступны", output.getvalue())

    def test_natal_bazi_uses_birth_moment(self):
        output = io.StringIO()
        with patch.object(astro, "sun_lon", return_value=44), patch.object(astro, "pillars", wraps=astro.pillars) as pillars, contextlib.redirect_stdout(output):
            astro.show_bazi(date(2026, 6, 1))
        self.assertEqual(pillars.call_args_list[1].args, (astro.BIRTH_UTC,))
        self.assertIn("справочный, не вычисленный", output.getvalue())


@unittest.skipUnless(real_swe is not None, "swisseph not installed locally")
class SwissIntegrationTests(unittest.TestCase):
    def test_transit_longitudes_and_natal_house_overlay(self):
        cli = load_cli(real_swe, "astro_cli_real_overlay")
        expected = [225.800256, 213.330486, 217.862902, 203.552294,
                    142.163330, 145.136947, 8.863038, 64.403389,
                    1.942677, 303.194895]
        pos = cli.positions(cli.jd_of(cli.moment(date(2026, 11, 8))))
        for (name, longitude, _), reference in zip(pos, expected):
            with self.subTest(planet=name):
                self.assertAlmostEqual(longitude, reference, delta=1e-4)
        natal_cusps = real_swe.houses(cli.jd_of(cli.BIRTH_UTC), cli.BIRTH_LAT,
                                     cli.BIRTH_LON, b"P")[0]
        for index, house in [(1, 1), (0, 2), (7, 8)]:
            self.assertEqual(cli.house_of(pos[index][1], natal_cusps), house)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            cli.show_transits(date(2026, 11, 8))
        lines = output.getvalue().splitlines()
        for index, house in [(1, 1), (0, 2), (7, 8)]:
            line = next(line for line in lines if line.startswith("  " + pos[index][0] + ":"))
            self.assertIn("дом %d" % house, line)
        self.assertNotIn("ASC", output.getvalue())

    def test_real_speed_houses_and_hour(self):
        cli = load_cli(real_swe, "astro_cli_real")
        jd = cli.jd_of(cli.BIRTH_UTC)
        longitude, speed = cli.lon_of(jd, real_swe.MERCURY)
        self.assertAlmostEqual(longitude, 23.2887393343453, delta=1e-4)
        self.assertAlmostEqual(speed, 0.14784419622750875, delta=1e-4)
        self.assertGreater(speed, 0)
        pos, cusps, ascmc = cli.chart(jd)
        self.assertEqual(len(cusps), 12)
        self.assertEqual(len(pos), 10)
        self.assertTrue(0 <= ascmc[0] < 360)
        self.assertEqual(cli.natal_hour(6)[:2], (0, 8))
        self.assertEqual(cli.pillars(cli.BIRTH_UTC)[2], (6, 2))


BASH = shutil.which("bash")


@unittest.skipUnless(BASH is not None, "Bash not installed locally")
class WrapperTests(unittest.TestCase):
    def run_wrapper(self, name, fail_at):
        # Fixtures only: never access the real configured output or CLI.
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            out = folder / "published.md"
            out.write_text("previous complete output", encoding="utf-8")
            cli = folder / "fake-cli"
            count = folder / "count"
            cli.write_text("#!/usr/bin/env bash\nset -eu\n"
                           f"N=0; if [ -f '{count.as_posix()}' ]; then N=$(cat '{count.as_posix()}'); fi\n"
                           f"N=$((N+1)); echo $N > '{count.as_posix()}'\n"
                           f"echo partial; if [ $N = {fail_at} ]; then echo failed >&2; exit 7; fi\n"
                           "echo complete\n", encoding="utf-8")
            cli.chmod(0o755)
            source = (ROOT / "deploy/scripts" / name).read_text(encoding="utf-8")
            lines = source.splitlines()
            for i, line in enumerate(lines):
                if line.startswith("OUT="):
                    lines[i] = "OUT='" + out.as_posix() + "'"
                elif line.startswith("CLI="):
                    lines[i] = "CLI='" + cli.as_posix() + "'"
                elif line.startswith("LOG="):
                    lines[i] = "LOG='" + (folder / "log").as_posix() + "'"
            script = folder / "wrapper.sh"
            script.write_text("\n".join(lines) + "\n", encoding="utf-8")
            result = subprocess.run([BASH, str(script)], capture_output=True, text=True)
            text = out.read_text(encoding="utf-8")
            self.assertFalse(list(folder.glob("published.md.tmp.*")))
            if fail_at:
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertEqual(text, "previous complete output")
            else:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("08:00 МСК", text)
                self.assertIn("Europe/Moscow", text)
                self.assertIn("complete", text)
                self.assertNotIn("failed", text)
            return text

    def test_daily_failure(self):
        self.run_wrapper("astro-daily.sh", 1)

    def test_weekly_later_failure(self):
        self.run_wrapper("astro-weekly.sh", 4)

    def test_daily_success(self):
        self.run_wrapper("astro-daily.sh", 0)

    def test_weekly_success(self):
        text = self.run_wrapper("astro-weekly.sh", 0)
        self.assertEqual(text.count("\n## "), 7)


if __name__ == "__main__":
    unittest.main()
