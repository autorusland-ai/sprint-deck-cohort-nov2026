#!/bin/bash
# Напоминание: Пятница — чат Итоги недели
BOT_TOKEN="$(cat ~/.openclaw/secrets/telegram.token)"
CHAT_ID="215087477"

curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
  -d "chat_id=$CHAT_ID" \
  -d "text=📋 Пятница — время подвести итоги недели!

Загляни в чат с Иванычем, посмотрим что сделано, что не успел, зафиксируем метрики." \
  -d "disable_notification=false" > /dev/null
