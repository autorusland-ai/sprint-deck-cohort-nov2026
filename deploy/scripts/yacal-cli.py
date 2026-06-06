#!/home/clawd/browser-env/bin/python3.12
"""
Yandex Calendar CLI через CalDAV. Бот вызывает через `exec`.

Usage:
  yacal-cli.py list-calendars
  yacal-cli.py today                                 # primary календарь, сегодня в МСК
  yacal-cli.py range <iso_start> <iso_end>           # primary
  yacal-cli.py range <iso_start> <iso_end> --calendar <name>
  yacal-cli.py add "<summary>" <iso_start> <iso_end> [--description "<text>"] [--calendar <name>]
  yacal-cli.py delete <event_uid> [--calendar <name>]

Все ISO даты с TZ offset +03:00, например 2026-06-04T21:00:00+03:00.
"""
import sys
import json
import os
import argparse
from datetime import datetime, timezone, timedelta
import uuid

try:
    import caldav
    from caldav.elements import dav
    from icalendar import Calendar, Event
except ImportError as e:
    print(json.dumps({'error': True, 'msg': f'missing package: {e}. pip install caldav icalendar'}))
    sys.exit(1)

CREDS_FILE = '/home/clawd/.openclaw/secrets/yandex-caldav.json'
MSK = timezone(timedelta(hours=3))


def get_client():
    creds = json.load(open(CREDS_FILE))
    return caldav.DAVClient(url=creds['url'], username=creds['username'], password=creds['password'])


def get_calendar(client, name=None):
    principal = client.principal()
    cals = principal.calendars()
    if not cals:
        raise RuntimeError('No calendars found')
    if name is None:
        # Primary календарь — обычно первый или с именем совпадающим с логином
        return cals[0]
    for c in cals:
        cname = c.name or ''
        if name.lower() in cname.lower():
            return c
    raise RuntimeError(f'Calendar "{name}" not found. Available: {[c.name for c in cals]}')


def serialize_event(comp):
    """Вытащить нужные поля из VEVENT компонента."""
    def to_str(prop):
        v = comp.get(prop)
        if v is None:
            return None
        if hasattr(v, 'dt'):
            dt = v.dt
            if isinstance(dt, datetime):
                return dt.isoformat()
            return dt.isoformat()
        return str(v)

    return {
        'uid': str(comp.get('uid', '')),
        'summary': str(comp.get('summary', '')),
        'description': str(comp.get('description', ''))[:500],
        'location': str(comp.get('location', '')),
        'start': to_str('dtstart'),
        'end': to_str('dtend'),
        'status': str(comp.get('status', 'CONFIRMED')),
    }


def cmd_list_calendars():
    client = get_client()
    principal = client.principal()
    return [{'name': c.name, 'url': str(c.url)} for c in principal.calendars()]


def cmd_range(start, end, calendar_name=None):
    client = get_client()
    cal = get_calendar(client, calendar_name)
    start_dt = datetime.fromisoformat(start)
    end_dt = datetime.fromisoformat(end)
    events = cal.search(start=start_dt, end=end_dt, event=True, expand=True)
    out = []
    for ev in events:
        ical = Calendar.from_ical(ev.data)
        for comp in ical.walk('VEVENT'):
            out.append(serialize_event(comp))
    out.sort(key=lambda e: e.get('start') or '')
    return out


def cmd_today(calendar_name=None):
    now = datetime.now(MSK)
    start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + timedelta(days=1)
    return cmd_range(start.isoformat(), end.isoformat(), calendar_name)


def cmd_add(summary, start, end, description='', calendar_name=None):
    client = get_client()
    cal = get_calendar(client, calendar_name)
    start_dt = datetime.fromisoformat(start)
    end_dt = datetime.fromisoformat(end)
    uid = str(uuid.uuid4()) + '@ivanich-bot'

    ical = Calendar()
    ical.add('prodid', '-//Ivanich Bot//Yandex CalDAV//EN')
    ical.add('version', '2.0')
    event = Event()
    event.add('uid', uid)
    event.add('summary', summary)
    event.add('dtstart', start_dt)
    event.add('dtend', end_dt)
    if description:
        event.add('description', description)
    event.add('dtstamp', datetime.now(timezone.utc))
    ical.add_component(event)

    new_event = cal.save_event(ical.to_ical().decode())
    return {'uid': uid, 'url': str(new_event.url), 'summary': summary, 'start': start, 'end': end}


def cmd_delete(uid, calendar_name=None):
    client = get_client()
    cal = get_calendar(client, calendar_name)
    try:
        ev = cal.event_by_uid(uid)
        ev.delete()
        return {'deleted': uid}
    except Exception as e:
        return {'error': True, 'msg': str(e)}


def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    args = sys.argv[1:]
    cmd = args[0]

    def get_opt(name):
        if '--' + name in args:
            return args[args.index('--' + name) + 1]
        return None

    try:
        if cmd == 'list-calendars':
            result = cmd_list_calendars()
        elif cmd == 'today':
            result = cmd_today(get_opt('calendar'))
        elif cmd == 'range':
            result = cmd_range(args[1], args[2], get_opt('calendar'))
        elif cmd == 'add':
            result = cmd_add(args[1], args[2], args[3], get_opt('description') or '', get_opt('calendar'))
        elif cmd == 'delete':
            result = cmd_delete(args[1], get_opt('calendar'))
        else:
            print(f'Unknown command: {cmd}'); print(__doc__); sys.exit(2)
        print(json.dumps(result, ensure_ascii=False, indent=2, default=str))
    except Exception as e:
        print(json.dumps({'error': True, 'msg': str(e), 'type': type(e).__name__}, ensure_ascii=False))
        sys.exit(1)


if __name__ == '__main__':
    main()
