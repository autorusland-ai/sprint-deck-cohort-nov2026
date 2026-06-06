#!/home/clawd/browser-env/bin/python3.12
"""
Хелпер для Google Workspace API: бот вызывает через `exec`.
Авто-обновляет access_token из refresh_token (в openclaw.json env).

Usage:
  gws-cli.py gmail unread-count
  gws-cli.py gmail search "is:unread" [--limit 10]
  gws-cli.py gmail message <message_id>
  gws-cli.py gmail send <to> <subject> <body>
  gws-cli.py calendar today
  gws-cli.py calendar range <iso_start> <iso_end>
  gws-cli.py calendar add <summary> <iso_start> <iso_end> [--description X]
"""
import sys, json, os, argparse, time, base64
from email.mime.text import MIMEText
from urllib.request import Request, urlopen
from urllib.parse import urlencode
from urllib.error import HTTPError

CFG = '/home/clawd/.openclaw/openclaw.json'
TOKEN_CACHE = '/tmp/gws-access-token.json'

def get_creds():
    d = json.load(open(CFG))
    env = d['env']
    return env['GOOGLE_OAUTH_CLIENT_ID' if 'GOOGLE_OAUTH_CLIENT_ID' in env else 'GOOGLE_WORKSPACE_CLIENT_ID'],            env['GOOGLE_OAUTH_CLIENT_SECRET' if 'GOOGLE_OAUTH_CLIENT_SECRET' in env else 'GOOGLE_WORKSPACE_CLIENT_SECRET'],            env['GOOGLE_WORKSPACE_REFRESH_TOKEN']

def get_access_token():
    # cache на 50 минут (Google access_token expires_in=3600)
    if os.path.exists(TOKEN_CACHE):
        try:
            cached = json.load(open(TOKEN_CACHE))
            if cached['expires_at'] > time.time() + 60:
                return cached['access_token']
        except Exception:
            pass
    cid, csec, rtok = get_creds()
    body = urlencode({'client_id': cid, 'client_secret': csec, 'refresh_token': rtok, 'grant_type': 'refresh_token'}).encode()
    req = Request('https://oauth2.googleapis.com/token', data=body)
    with urlopen(req, timeout=15) as r:
        data = json.loads(r.read())
    access = data['access_token']
    json.dump({'access_token': access, 'expires_at': time.time() + data.get('expires_in', 3600)}, open(TOKEN_CACHE, 'w'))
    os.chmod(TOKEN_CACHE, 0o600)
    return access

def api(method, url, *, params=None, body=None):
    if params:
        url = url + ('&' if '?' in url else '?') + urlencode(params)
    headers = {'Authorization': 'Bearer ' + get_access_token()}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers['Content-Type'] = 'application/json'
    req = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=30) as r:
            return json.loads(r.read())
    except HTTPError as e:
        return {'error': True, 'status': e.code, 'body': e.read().decode()[:500]}

def cmd_gmail_unread_count():
    r = api('GET', 'https://gmail.googleapis.com/gmail/v1/users/me/labels/UNREAD')
    if r.get('error'): return r
    return {'unread_threads': r.get('threadsUnread', 0), 'unread_messages': r.get('messagesUnread', 0)}

def cmd_gmail_search(query, limit=10):
    r = api('GET', 'https://gmail.googleapis.com/gmail/v1/users/me/messages', params={'q': query, 'maxResults': limit})
    if r.get('error'): return r
    out = []
    for m in r.get('messages', []):
        d = api('GET', f'https://gmail.googleapis.com/gmail/v1/users/me/messages/{m["id"]}', params={'format': 'metadata', 'metadataHeaders': 'From,Subject,Date'})
        hdr = {h['name']: h['value'] for h in d.get('payload', {}).get('headers', [])}
        out.append({'id': m['id'], 'from': hdr.get('From',''), 'subject': hdr.get('Subject',''), 'date': hdr.get('Date',''), 'snippet': d.get('snippet','')[:200]})
    return out

def cmd_gmail_message(mid):
    return api('GET', f'https://gmail.googleapis.com/gmail/v1/users/me/messages/{mid}', params={'format': 'full'})

def cmd_gmail_send(to, subject, body):
    msg = MIMEText(body, 'plain', 'utf-8')
    msg['to'] = to; msg['subject'] = subject
    raw = base64.urlsafe_b64encode(msg.as_bytes()).decode()
    return api('POST', 'https://gmail.googleapis.com/gmail/v1/users/me/messages/send', body={'raw': raw})

def cmd_cal_range(start, end):
    r = api('GET', 'https://www.googleapis.com/calendar/v3/calendars/primary/events',
            params={'timeMin': start, 'timeMax': end, 'singleEvents': 'true', 'orderBy': 'startTime'})
    if r.get('error'): return r
    return [{'id': e['id'], 'summary': e.get('summary',''), 'start': e.get('start',{}), 'end': e.get('end',{}), 'description': e.get('description','')[:300]} for e in r.get('items', [])]

def cmd_cal_today():
    from datetime import datetime, timezone, timedelta
    now = datetime.now(timezone(timedelta(hours=3)))
    start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + timedelta(days=1)
    return cmd_cal_range(start.isoformat(), end.isoformat())

def cmd_cal_add(summary, start, end, description=''):
    body = {'summary': summary, 'start': {'dateTime': start}, 'end': {'dateTime': end}}
    if description: body['description'] = description
    return api('POST', 'https://www.googleapis.com/calendar/v3/calendars/primary/events', body=body)

def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    cmd = sys.argv[1:]
    try:
        if cmd[:2] == ['gmail','unread-count']: result = cmd_gmail_unread_count()
        elif cmd[:2] == ['gmail','search']: result = cmd_gmail_search(cmd[2], int(cmd[cmd.index('--limit')+1]) if '--limit' in cmd else 10)
        elif cmd[:2] == ['gmail','message']: result = cmd_gmail_message(cmd[2])
        elif cmd[:2] == ['gmail','send']: result = cmd_gmail_send(cmd[2], cmd[3], cmd[4])
        elif cmd[:2] == ['calendar','today']: result = cmd_cal_today()
        elif cmd[:2] == ['calendar','range']: result = cmd_cal_range(cmd[2], cmd[3])
        elif cmd[:2] == ['calendar','add']: result = cmd_cal_add(cmd[2], cmd[3], cmd[4], cmd[cmd.index('--description')+1] if '--description' in cmd else '')
        else:
            print('unknown command:', ' '.join(cmd)); print(__doc__); sys.exit(2)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except Exception as e:
        print(json.dumps({'error': True, 'exception': str(e)}, ensure_ascii=False))
        sys.exit(1)

if __name__ == '__main__':
    main()
