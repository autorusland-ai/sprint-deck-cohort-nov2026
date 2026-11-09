#!/home/clawd/browser-env/bin/python3.12
"""Локальный расчёт: astro-cli.py {all,transits,bazi,natal} [YYYY-MM-DD].
Дата по Москве, транзиты и дневные столпы на 08:00 МСК.
Планеты — Swiss Ephemeris/Moshier; Хирон требует файлов эфемерид.
"""
import sys
from datetime import datetime, date, timedelta, timezone

import swisseph as swe

swe.set_ephe_path(None)
FLAGS = swe.FLG_MOSEPH | swe.FLG_SPEED
MSK = timezone(timedelta(hours=3))
# Историческое гражданское смещение для рождения — UTC+10.
BIRTH_UTC = datetime(1971, 5, 5, 17, 5, tzinfo=timezone(timedelta(hours=10)))
BIRTH_LAT, BIRTH_LON = 43.80, 131 + 59 / 60
PLANETS = [
    ("Солнце", swe.SUN), ("Луна", swe.MOON), ("Меркурий", swe.MERCURY),
    ("Венера", swe.VENUS), ("Марс", swe.MARS), ("Юпитер", swe.JUPITER),
    ("Сатурн", swe.SATURN), ("Уран", swe.URANUS), ("Нептун", swe.NEPTUNE),
    ("Плутон", swe.PLUTO),
]
SIGNS = ["Овна", "Тельца", "Близнецов", "Рака", "Льва", "Девы",
         "Весов", "Скорпиона", "Стрельца", "Козерога", "Водолея", "Рыб"]
ASPECTS = [(0, "соединение", 6), (60, "секстиль", 3), (90, "квадратура", 5),
           (120, "трин", 5), (180, "оппозиция", 6)]
STEMS = "甲 乙 丙 丁 戊 己 庚 辛 壬 癸".split()
STEMS_RU = ["Ян Дерево", "Инь Дерево", "Ян Огонь", "Инь Огонь", "Ян Земля",
            "Инь Земля", "Ян Металл", "Инь Металл", "Ян Вода", "Инь Вода"]
BRANCHES = "子 丑 寅 卯 辰 巳 午 未 申 酉 戌 亥".split()
BRANCHES_RU = ["Крыса", "Бык", "Тигр", "Кролик", "Дракон", "Змея",
               "Лошадь", "Коза", "Обезьяна", "Петух", "Собака", "Свинья"]
MONTH_BRANCH_ORDER = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 0, 1]


def moment(d):
    """Дата означает 08:00 МСК; переданный точный момент не округляется."""
    if isinstance(d, datetime):
        if d.tzinfo is None or d.utcoffset() is None:
            raise ValueError("Нужен момент с часовым поясом")
        return d
    return datetime(d.year, d.month, d.day, 8, tzinfo=MSK)


def jd_of(dt):
    u = dt.astimezone(timezone.utc)
    hour = u.hour + u.minute / 60 + (u.second + u.microsecond / 1e6) / 3600
    return swe.julday(u.year, u.month, u.day, hour)


def lon_of(jd, planet):
    vals, _flag = swe.calc_ut(jd, planet, FLAGS)
    return vals[0], vals[3]


def fmt(lon):
    minutes = int(round((lon % 360) * 60)) % (360 * 60)
    sign, within = divmod(minutes, 30 * 60)
    degree, minute = divmod(within, 60)
    return "%d°%02d' %s" % (degree, minute, SIGNS[sign])


def positions(jd):
    return [(name, *lon_of(jd, pid)) for name, pid in PLANETS]


def chart(jd):
    cusps, ascmc = swe.houses(jd, BIRTH_LAT, BIRTH_LON, b"P")
    return positions(jd), cusps, ascmc


def natal():
    pos, _cusps, ascmc = chart(jd_of(BIRTH_UTC))
    return pos, ascmc[0]


def house_of(lon, cusps):
    """Номер дома по эклиптическим интервалам рассчитанных куспидов."""
    if len(cusps) != 12:
        raise ValueError("Требуются 12 куспидов")
    for i, start in enumerate(cusps):
        if (lon - start) % 360 < (cusps[(i + 1) % 12] - start) % 360:
            return i + 1
    raise ValueError("Некорректные куспиды")


def show_position(name, lon, speed, cusps):
    print("  %s: %s; дом %d%s" %
          (name, fmt(lon), house_of(lon, cusps), "; ретро" if speed < 0 else ""))


def show_chart(jd):
    pos, cusps, ascmc = chart(jd)
    print("  Дома Плацидуса, координаты %.6f, %.6f" % (BIRTH_LAT, BIRTH_LON))
    print("  ASC %s; MC %s" % (fmt(ascmc[0]), fmt(ascmc[1])))
    for i, cusp in enumerate(cusps, 1):
        print("  Куспид %d: %s" % (i, fmt(cusp)))
    for name, lon, speed in pos:
        show_position(name, lon, speed, cusps)
    for label, pid in [("Северный узел mean (средний)", swe.MEAN_NODE),
                       ("Северный узел true (истинный)", swe.TRUE_NODE)]:
        lon, speed = lon_of(jd, pid)
        show_position(label, lon, speed, cusps)
    try:
        lon, speed = lon_of(jd, swe.CHIRON)
    except swe.Error:
        print("  Хирон: недоступен (нет подходящих эфемерид)")
    else:
        show_position("Хирон", lon, speed, cusps)
    return pos


def show_natal():
    print("НАТАЛЬНАЯ КАРТА (05.05.1971, 17:05 UTC+10, Уссурийск)")
    show_chart(jd_of(BIRTH_UTC))


def aspect_lines(tpos, npos):
    found = []
    for tname, tlon, _ in tpos:
        for nname, nlon, _ in npos:
            diff = abs((tlon - nlon + 180) % 360 - 180)
            for angle, name, orb in ASPECTS:
                delta = abs(diff - angle)
                if delta <= orb:
                    line = "  транзитный %s %s натальному %s (%.1f°)" % (
                        tname, name, nname, delta)
                    if delta > 3:
                        line += " — слабый сигнал"
                    found.append((delta, line))
    return [line for _, line in sorted(found)]


def extra_aspect_targets(jd):
    """Выбран mean-узел; true-узел выводится отдельно, без смешения моделей."""
    out = [("Северному узлу mean (средний)", *lon_of(jd, swe.MEAN_NODE))]
    try:
        out.append(("Хирону", *lon_of(jd, swe.CHIRON)))
    except swe.Error:
        pass
    return out


def show_transits(d):
    natal_jd = jd_of(BIRTH_UTC)
    npos, natal_cusps, _ascmc = chart(natal_jd)
    transit_jd = jd_of(moment(d))
    print("ТРАНЗИТЫ на %s (08:00 МСК)" % d.strftime("%d.%m.%Y"))
    print("  Дома транзитных планет: наложение на НАТАЛЬНЫЕ куспиды Плацидуса.")
    tpos = positions(transit_jd)
    for name, lon, speed in tpos:
        show_position(name, lon, speed, natal_cusps)
    for label, pid in [("Северный узел mean (средний)", swe.MEAN_NODE),
                       ("Северный узел true (истинный), справочно", swe.TRUE_NODE)]:
        lon, speed = lon_of(transit_jd, pid)
        show_position(label, lon, speed, natal_cusps)
    try:
        lon, speed = lon_of(transit_jd, swe.CHIRON)
    except swe.Error:
        print("  Хирон: недоступен (нет подходящих эфемерид)")
    else:
        show_position("Хирон", lon, speed, natal_cusps)
    print("\nАСПЕКТЫ к натальным планетам (орб в скобках; >3° — слабый сигнал):")
    lines = aspect_lines(tpos, npos)
    print("\n".join(lines) if lines else "  аспектов в пределах орбов нет")
    print("\nДОПОЛНИТЕЛЬНЫЕ АСПЕКТЫ к натальному mean-узлу и Хирону:")
    print("  Модель узла: mean (средний); true — только справочные координаты.")
    targets = extra_aspect_targets(natal_jd)
    if len(targets) == 1:
        print("  Аспекты к натальному Хирону недоступны: нет эфемерид.")
    lines = aspect_lines(tpos, targets)
    print("\n".join(lines) if lines else "  аспектов в пределах орбов нет")


def sun_lon(jd):
    return lon_of(jd, swe.SUN)[0]


def solar_term_index(d):
    """Месяц от Личунь 315° по Солнцу в точный момент."""
    return int(((sun_lon(jd_of(moment(d))) - 315) % 360) // 30)


def pillars(d):
    dt = moment(d)
    sl = sun_lon(jd_of(dt)) % 360
    # Январь относится к предыдущему году; февраль — до точного Личунь.
    y = dt.year - int(dt.month == 1 or (dt.month == 2 and sl < 315))
    yi = (y - 1984) % 60
    ys, yb = yi % 10, yi % 12
    # Сохраняем проверенный якорь 2000-01-01, индекс 54 (戊午).
    anchor, anchor_index = date(2000, 1, 1), 54
    di = (anchor_index + (dt.date() - anchor).days) % 60
    ds, db = di % 10, di % 12
    month_index = int(((sl - 315) % 360) // 30)
    mb = MONTH_BRANCH_ORDER[month_index]
    ms = (2 * (ys % 5) + 2 + month_index) % 10
    return (ys, yb), (ms, mb), (ds, db), y


def gz(s, b):
    return "%s%s (%s %s)" % (STEMS[s], BRANCHES[b], STEMS_RU[s], BRANCHES_RU[b])


def ten_god(day_stem, other_stem):
    """Пять отношений элементов и полярность стволов."""
    relation = (other_stem // 2 - day_stem // 2) % 5
    opposite = day_stem % 2 != other_stem % 2
    return [("比肩", "劫财"), ("食神", "伤官"), ("偏财", "正财"),
            ("七杀", "正官"), ("偏印", "正印")][relation][opposite]


def natal_hour(day_stem):
    # swe.time_equ: apparent - mean solar time, в долях суток.
    eot_minutes = swe.time_equ(jd_of(BIRTH_UTC)) * 1440
    solar = BIRTH_UTC + timedelta(minutes=eot_minutes + 4 * (BIRTH_LON - 150))
    minutes = solar.hour * 60 + solar.minute + solar.second / 60 + solar.microsecond / 6e7
    branch = int(((minutes + 60) // 120) % 12)
    stem = (2 * (day_stem % 5) + branch) % 10
    return stem, branch, solar


def show_bazi(d):
    (ys, yb), (ms, mb), (ds, db), y = pillars(d)
    print("БАЦЗЫ на %s (08:00 МСК)" % d.strftime("%d.%m.%Y"))
    print("  Столп года: %s [год %d; граница Личунь, Солнце 315°]" % (gz(ys, yb), y))
    print("  Столп месяца: %s" % gz(ms, mb))
    print("  Столп дня: %s" % gz(ds, db))
    (nys, nyb), (nms, nmb), (nds, ndb), _ = pillars(BIRTH_UTC)
    print("\n  НАТАЛЬНЫЕ СТОЛПЫ (точный момент рождения 17:05 UTC+10)")
    print("  Столп года рождения: %s" % gz(nys, nyb))
    print("  Столп месяца рождения: %s" % gz(nms, nmb))
    print("  Столп дня рождения: %s; ГОСПОДИН ДНЯ %s" % (gz(nds, ndb), STEMS[nds]))
    hs, hb, solar = natal_hour(nds)
    print("  Столп часа рождения: %s [истинное солнечное время %s; EoT + долгота]" %
          (gz(hs, hb), solar.strftime("%H:%M:%S")))
    print("  Десять богов к Господину дня: " + "; ".join(
        STEMS[s] + "=" + ten_god(nds, s) for s in range(10)))
    print("  Такт удачи 2021–2031: 丁亥 (справочный, не вычисленный)")


def main():
    args = sys.argv[1:] or ["all"]
    if len(args) > 2 or args[0] not in {"all", "transits", "bazi", "natal"}:
        print(__doc__, file=sys.stderr)
        return 2
    d = date.fromisoformat(args[1]) if len(args) > 1 else datetime.now(MSK).date()
    cmd = args[0]
    if cmd == "natal":
        show_natal()
    elif cmd == "transits":
        show_transits(d)
    elif cmd == "bazi":
        show_bazi(d)
    else:
        show_natal()
        print()
        show_transits(d)
        print()
        show_bazi(d)
    return 0


if __name__ == "__main__":
    sys.exit(main())
