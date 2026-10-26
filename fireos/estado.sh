#!/usr/bin/env bash
# Solo lectura: ¿está vivo el servicio de Home? ¿tronó algo? Guarda todo en fireos/estado.txt
# Uso:   TV_HOST=192.168.1.70 bash fireos/estado.sh
. "$(dirname "$0")/_comun.sh"
show() { echo "### $1"; tv "$1" 2>&1; echo; }
{
  echo "servicio conectado: $(bound)"
  echo "al frente: $(resumed)"
  echo
  show 'cat /proc/uptime; settings get secure enabled_accessibility_services; settings get secure accessibility_enabled; settings get global alarm_manager_constants'
  show 'dumpsys accessibility | head -20'
  show "pidof $PKG; dumpsys package $PKG | grep -E 'versionCode|lastUpdateTime|stopped=' | head -5"
  show 'logcat -b crash -d | tail -60'
  show 'logcat -d -v time | grep -E "FireHome|HomeKeyService|gathin|AndroidRuntime|ccessibilityManager" | tail -60'
} > fireos/estado.txt 2>&1
echo "Servicio de Home conectado: $( [ "$(bound)" = 1 ] && echo sí || echo NO ). Detalle en fireos/estado.txt"
