#!/usr/bin/env python3
# ============================================================================
# reauth-google.py — перевыпуск Google OAuth refresh-токена (Gmail + Calendar)
# ============================================================================
# Запускается НА VPS, нужен браузер на твоём компьютере + проброс порта SSH.
#
# С локальной машины (PowerShell/bash):
#   scp -i ~/.ssh/clawd_ed25519 scripts/reauth-google.py clawd@$VPS_IP:~/reauth-google.py
#   ssh -t -L 8765:localhost:8765 -i ~/.ssh/clawd_ed25519 clawd@$VPS_IP \
#       "~/browser-env/bin/python ~/reauth-google.py"
#
# Скрипт напечатает ссылку → открой её в браузере на компьютере → дай согласие.
# Редирект на localhost:8765 уйдёт по туннелю на VPS, токен сохранится в
# ~/.config/google-oauthlib-tool/credentials.json.
#
# Потом (с локальной машины) пропиши новый токен в .env и на VPS:
#   scp ...:~/.config/google-oauthlib-tool/credentials.json /tmp/g.json
#   # GOOGLE_WORKSPACE_REFRESH_TOKEN = (refresh_token из g.json) → .env + config → deploy.sh
# ============================================================================
import os, json
from google_auth_oauthlib.flow import InstalledAppFlow

CLIENT = os.path.expanduser("~/.openclaw/secrets/google-oauth.json")
CREDS_OUT = os.path.expanduser("~/.config/google-oauthlib-tool/credentials.json")
SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/calendar",   # полный read+write
]
PORT = 8765

flow = InstalledAppFlow.from_client_secrets_file(CLIENT, scopes=SCOPES)
creds = flow.run_local_server(
    host="localhost", port=PORT, open_browser=False,
    access_type="offline", prompt="consent",
    authorization_prompt_message="\n>>> ОТКРОЙ ЭТУ ССЫЛКУ В БРАУЗЕРЕ НА СВОЁМ КОМПЬЮТЕРЕ:\n\n{url}\n",
    success_message="Готово! Закрой вкладку и вернись в терминал.",
)
os.makedirs(os.path.dirname(CREDS_OUT), exist_ok=True)
json.dump({
    "refresh_token": creds.refresh_token,
    "token": creds.token,
    "token_uri": creds.token_uri,
    "client_id": creds.client_id,
    "client_secret": creds.client_secret,
    "scopes": list(creds.scopes or []),
}, open(CREDS_OUT, "w"), indent=2)
print("\n=== SAVED:", CREDS_OUT)
print("=== granted scopes:", creds.scopes)
print("=== has refresh_token:", bool(creds.refresh_token))
