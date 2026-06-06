#!/usr/bin/env bash
mkdir -p ~/.openclaw/workspace/archive
find ~/.openclaw/workspace/memory/ -name "*.md" -mtime +30 -exec mv {} ~/.openclaw/workspace/archive/ \;
