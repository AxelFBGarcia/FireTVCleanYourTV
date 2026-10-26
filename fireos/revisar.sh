#!/usr/bin/env bash
# Solo lectura. Mide qué pasa al presionar Home en el inicio nuevo y busca cómo abrir la Appstore.
# Uso, desde la carpeta cleanyourtv:   TV_HOST=192.168.1.70 bash fireos/revisar.sh
cd "$(dirname "$0")/.." || exit 1
: "${TV_HOST:?pon TV_HOST=<ip de la tele>}"
OUT=fireos/revisar.txt
tv() { echo "### $1"; tools/venv/bin/python -I tools/tv.py "$1" 2>&1; echo; }
tools/venv/bin/python -I tools/tv.py 'logcat -c' >/dev/null 2>&1
echo
echo ">>> Deja la tele en el INICIO NUEVO (CleanYourTV)."
echo ">>> Presiona ENTER aquí, y luego presiona HOME UNA VEZ con el control remoto y espera."
read -r _
echo "Grabando 10 segundos..."
sleep 10
{
  echo "## HOME desde el inicio nuevo"
  tv 'logcat -d -v time | grep -E "FireHome|HomeKeyService|ActivityManager.*(START u0|Displayed|resumeTopActivity)|app.?switch|Changing focus" | head -150'
  tv 'dumpsys activity activities | grep -E "mResumedActivity|Run #" | head -12'
  echo "## APPSTORE"
  tv 'pm list packages | grep -i -E "venezia|appstore"'
  tv 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER com.amazon.venezia'
  tv 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER com.amazon.venezia'
  tv 'cmd package resolve-activity --brief -a com.amazon.venezia.ade.FEATURED_LAUNCH com.amazon.venezia'
  tv 'dumpsys package com.amazon.venezia | grep -E "^ *(Action|Category):|com.amazon.venezia/[^ ]*Activity" | sort -u | head -80'
  echo "## OTRAS APPS SIN ICONO (tienen actividad principal pero no de lanzador)"
  tv 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER | grep "/" | sort'
} > "$OUT" 2>&1
echo "Listo: $OUT. Avísale a Claude."
