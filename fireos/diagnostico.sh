#!/usr/bin/env bash
# Solo lectura: no cambia nada en la tele ni en la Mac. Guarda todo en fireos/diagnostico.txt
# Uso (desde la carpeta cleanyourtv):  TV_HOST=192.168.1.70 bash fireos/diagnostico.sh
cd "$(dirname "$0")/.." || exit 1
: "${TV_HOST:?pon TV_HOST=<ip de la tele>}"
OUT=fireos/diagnostico.txt
tv() { echo "### $1"; tools/venv/bin/python -I tools/tv.py "$1" 2>&1; echo; }
{
  echo "## MAC"
  sw_vers 2>&1; uname -m
  echo "### java_home -V"; /usr/libexec/java_home -V 2>&1
  for j in "/Applications/Android Studio.app/Contents/jbr/Contents/Home" "/Applications/Android Studio.app/Contents/jre/Contents/Home"; do
    [ -x "$j/bin/java" ] && { echo "### JBR: $j"; "$j/bin/java" -version 2>&1; }
  done
  echo "### Android SDK"; ls ~/Library/Android/sdk 2>&1; ls ~/Library/Android/sdk/platforms ~/Library/Android/sdk/build-tools 2>&1
  echo; echo "## TV"
  tv 'getprop ro.build.version.name; getprop ro.build.display.id; getprop ro.product.model'
  tv 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME'
  tv 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME'
  tv 'settings get secure enabled_accessibility_services; settings get secure accessibility_enabled'
  tv 'settings get global alarm_manager_constants'
  tv 'dumpsys activity activities | grep -E "mResumedActivity|mFocusedApp" | head -5'
  tv 'pm list packages | grep -i -E "tvinput|livetv|tv.input|mediatek" '
  tv 'dumpsys tv_input | grep -E "TvInputInfo|id=|type=" | head -40'
  tv 'pm list packages com.gathin; pm list packages com.firetv'
  tv 'dumpsys package com.amazon.tv.launcher | grep -E "versionName|HomeActivity|MainSettings" | head -20'
} > "$OUT" 2>&1
echo "Listo: $OUT ($(wc -l < "$OUT") líneas). Avísale a Claude."
