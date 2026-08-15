#!/home/clawd/browser-env/bin/python3.12
"""astro-cli.py — расчёт транзитов и Бацзы локально, без обращения к сайтам.

Зачем: астрологические сайты закрыты Cloudflare и отдают 403 на автоматический
сбор, из-за чего утренний прогноз приходил с оговорками «источники недоступны».
Хуже того, без источников модель начинала выдавать конкретные градусы по памяти —
такие цифры невозможно отличить от выдуманных. Здесь всё считается из эфемерид
(swisseph, режим Moshier — файлы данных не нужны), результат воспроизводим.

Использование:
    astro-cli.py transits [ГГГГ-ММ-ДД]   транзиты и аспекты к натальной карте
    astro-cli.py bazi     [ГГГГ-ММ-ДД]   столпы года / месяца / дня
    astro-cli.py natal                   натальная карта (для сверки)
    astro-cli.py all      [ГГГГ-ММ-ДД]   всё сразу (по умолчанию — сегодня)

Дата без аргумента — сегодняшняя по Москве.
"""
import sys
from datetime import datetime, date, timedelta, timezone

import swisseph as swe

swe.set_ephe_path(None)
FLAGS = swe.FLG_SWIEPH | swe.FLG_MOSEPH  # Moshier: без файлов эфемерид

MSK = timezone(timedelta(hours=3))

# --- натальные данные Руслана (life/прогнозирование.md) ---------------------
BIRTH_UTC = datetime(1971, 5, 5, 17, 5, tzinfo=timezone(timedelta(hours=10)))
BIRTH_LAT, BIRTH_LON = 43.80, 131.95  # Уссурийск

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


def jd_of(dt):
    u = dt.astimezone(timezone.utc)
    return swe.julday(u.year, u.month, u.day, u.hour + u.minute / 60 + u.second / 3600)


def lon_of(jd, planet):
    """Возвращает (долгота, скорость). Скорость < 0 — планета ретроградна."""
    vals, _flag = swe.calc_ut(jd, planet, FLAGS)
    return vals[0], vals[3]


def fmt(lon):
    s = int(lon // 30) % 12
    d = lon % 30
    return "%d°%02d' %s" % (int(d), int(round((d - int(d)) * 60)) % 60, SIGNS[s])


def positions(jd):
    out = []
    for name, pid in PLANETS:
        lon, speed = lon_of(jd, pid)
        out.append((name, lon, speed))
    return out


def natal():
    jd = jd_of(BIRTH_UTC)
    pos = positions(jd)
    cusps, ascmc = swe.houses(jd, BIRTH_LAT, BIRTH_LON, b"P")
    return pos, ascmc[0]


def show_natal():
    pos, asc = natal()
    print("НАТАЛЬНАЯ КАРТА (05.05.1971, 17:05 UTC+10, Уссурийск)")
    for name, lon, _ in pos:
        print("  %-9s %s" % (name, fmt(lon)))
    print("  %-9s %s" % ("Асцендент", fmt(asc)))
    print("\n(сверка с life/прогнозирование.md: Солнце ~14°09' Тельца, Луна ~16°44' Девы)")


def show_transits(d):
    npos, _asc = natal()
    nmap = {n: l for n, l, _ in npos}
    jd = jd_of(datetime(d.year, d.month, d.day, 9, 0, tzinfo=MSK))
    print("ТРАНЗИТЫ на %s (09:00 МСК)" % d.strftime("%d.%m.%Y"))
    tpos = positions(jd)
    for name, lon, speed in tpos:
        print("  %-9s %s%s" % (name, fmt(lon), "  ретро" if speed < 0 else ""))

    print("\nАСПЕКТЫ к натальной карте (орб в скобках):")
    found = []
    for tname, tlon, _ in tpos:
        for nname, nlon in nmap.items():
            diff = abs((tlon - nlon + 180) % 360 - 180)
            for angle, aname, orb in ASPECTS:
                delta = abs(diff - angle)
                if delta <= orb:
                    found.append((delta, "  транзитный %s %s натальному %s (%.1f°)"
                                  % (tname, aname, nname, delta)))
    if found:
        for _, line in sorted(found):
            print(line)
    else:
        print("  точных аспектов в пределах орбов нет")


# --- Бацзы ------------------------------------------------------------------
STEMS = "甲 乙 丙 丁 戊 己 庚 辛 壬 癸".split()
STEMS_RU = ["Ян Дерево", "Инь Дерево", "Ян Огонь", "Инь Огонь", "Ян Земля",
            "Инь Земля", "Ян Металл", "Инь Металл", "Ян Вода", "Инь Вода"]
BRANCHES = "子 丑 寅 卯 辰 巳 午 未 申 酉 戌 亥".split()
BRANCHES_RU = ["Крыса", "Бык", "Тигр", "Кролик", "Дракон", "Змея",
               "Лошадь", "Коза", "Обезьяна", "Петух", "Собака", "Свинья"]
# Ветвь месяца по солнечному термину: месяц начинается, когда Солнце входит
# в 315°, 345°, 15° … (Лichun = 315° = месяц Тигра).
MONTH_BRANCH_ORDER = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 0, 1]  # от Тигра


def sun_lon(jd):
    return lon_of(jd, swe.SUN)[0]


def solar_term_index(d):
    """Сколько 15-градусных секторов Солнце прошло от 315° (Личунь)."""
    jd = jd_of(datetime(d.year, d.month, d.day, 12, 0, tzinfo=MSK))
    sl = sun_lon(jd)
    return int(((sl - 315) % 360) // 30)  # 0 = Тигр


def bazi_year_start(y):
    """Дата Личунь (Солнце 315°) в году y — начало года по Бацзы."""
    for day in range(1, 20):
        d = date(y, 2, day)
        jd = jd_of(datetime(d.year, d.month, d.day, 12, 0, tzinfo=MSK))
        if 315 <= sun_lon(jd) < 345:
            return d
    return date(y, 2, 4)


def pillars(d):
    # Год: 1984 = 甲子 (индекс 0), год начинается с Личунь
    y = d.year if d >= bazi_year_start(d.year) else d.year - 1
    yi = (y - 1984) % 60
    ys, yb = yi % 10, yi % 12

    # День: якорь 2000-01-01 = 戊午 (индекс 54). Проверен двумя способами:
    # независимый якорь 1900-01-01 = 甲戌 даёт тот же результат, и оба дают для
    # 05.05.1971 столп 庚寅 — Господин Дня 庚 совпадает с life/прогнозирование.md.
    # (Ходовой якорь «1984-02-02 = 甲子» этой проверки НЕ проходит — не брать.)
    anchor, anchor_index = date(2000, 1, 1), 54
    di = (anchor_index + (d - anchor).days) % 60
    ds, db = di % 10, di % 12

    # Месяц: ветвь по солнечному термину, ствол по «правилу пяти тигров»
    mb = MONTH_BRANCH_ORDER[solar_term_index(d)]
    ms = ((ys % 5) * 2 + MONTH_BRANCH_ORDER.index(mb)) % 10
    return (ys, yb), (ms, mb), (ds, db), y


def gz(s, b):
    return "%s%s (%s %s)" % (STEMS[s], BRANCHES[b], STEMS_RU[s], BRANCHES_RU[b])


def show_bazi(d):
    (ys, yb), (ms, mb), (ds, db), y = pillars(d)
    print("БАЦЗЫ на %s" % d.strftime("%d.%m.%Y"))
    print("  Столп года:   %s   [год по Бацзы: %d, с Личунь %s]"
          % (gz(ys, yb), y, bazi_year_start(y).strftime("%d.%m")))
    print("  Столп месяца: %s" % gz(ms, mb))
    print("  Столп дня:    %s" % gz(ds, db))
    # Натальные столпы печатаем ВСЕГДА и рядом с дневными: 15.08.2026 бот
    # прочитал столп дня верно, но столп рождения выдумал (сказал 戊午 вместо
    # 庚寅) и перевернул трактовку — «металл ослабляет твою землю», хотя Руслан
    # сам Металл. Данные должно быть неоткуда брать по памяти.
    (nys, nyb), (nms, nmb), (nds, ndb), _ = pillars(BIRTH_UTC.date())
    print("\n  --- НАТАЛЬНЫЕ СТОЛПЫ РУСЛАНА (не путать с сегодняшними) ---")
    print("  Столп года рождения:   %s" % gz(nys, nyb))
    print("  Столп месяца рождения: %s" % gz(nms, nmb))
    print("  Столп дня рождения:    %s  <-- ГОСПОДИН ДНЯ: %s (%s)"
          % (gz(nds, ndb), STEMS[nds], STEMS_RU[nds]))
    print("  Такт удачи 2021–2031: 丁亥")
    print("\n  ⚠️ Стихия Руслана — %s. Любую трактовку строй от неё, "
          "а не от вымышленной." % STEMS_RU[nds])


def main():
    args = sys.argv[1:] or ["all"]
    cmd = args[0]
    if len(args) > 1:
        d = datetime.strptime(args[1], "%Y-%m-%d").date()
    else:
        d = datetime.now(MSK).date()

    if cmd == "natal":
        show_natal()
    elif cmd == "transits":
        show_transits(d)
    elif cmd == "bazi":
        show_bazi(d)
    elif cmd == "all":
        show_transits(d)
        print()
        show_bazi(d)
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
