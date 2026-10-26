#!/usr/bin/env bash
# Solo lectura: ¿está vivo el servicio de Home? ¿tronó algo? Guarda todo en fireos/estado.txt
cd "$(dirname "$0")/.." || exit 1
: "${TV_HOST:?pon TV_HOST=<ip de la tele>}"
tv() { echo "### $1"; tools/venv/bin/python -I tools/tv.py "$1" 2>&1; echo; }
{
  tv 'cat /proc/uptime; settings get secure enabled_accessibility_services; settings get secure accessibility_enabled; settings get global alarm_manager_constants'
  tv 'dumpsys accessibility | head -20'
  tv 'pidof com.gathin.tvhome; dumpsys package com.gathin.tvhome | grep -E "versionCode|lastUpdateTime|stopped=" | head -5'
  tv 'logcat -b crash -d | tail -60'
  tv 'logcat -d -v time | grep -E "FireHome|HomeKeyService|TvHomeMenu|gathin|AndroidRuntime|ccessibilityManager" | head -60'
} > fireos/estado.txt 2>&1
echo "Listo: fireos/estado.txt. Avísale a Claude."
