#!/bin/bash
# Напоминание: Каждый день - чат Операционка
# Запускается в 9:30 МСК (= 6:30 UTC) по будням

BOT_TOKEN="$(cat ~/.openclaw/secrets/telegram.token)"
CHAT_ID="215087477"

curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
  -d "chat_id=$CHAT_ID" \
  -d "text=🔔 Напоминание: Каждый день — чат Операционка" \
  -d "disable_notification=false" > /dev/null
