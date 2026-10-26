#!/usr/bin/env bash
# Activa el servicio de Home y vigila 30 s si sigue activo y conectado. Guarda todo en fireos/activar.txt
cd "$(dirname "$0")/.." || exit 1
: "${TV_HOST:?pon TV_HOST=<ip de la tele>}"
tv() { tools/venv/bin/python -I tools/tv.py "$1" 2>&1; }
SVC=com.gathin.tvhome/.HomeKeyService
{
  tv 'logcat -c'
  echo "### activando $(date +%T)"
  tv "settings put secure enabled_accessibility_services $SVC; settings put secure accessibility_enabled 1; echo servicios=\$(settings get secure enabled_accessibility_services) activo=\$(settings get secure accessibility_enabled)"
  for t in 2 4 6 10 15 20 30; do
    sleep 2; [ $t -gt 6 ] && sleep 3
    echo "### +${t}s $(date +%T)"
    tv 'echo servicios=$(settings get secure enabled_accessibility_services) activo=$(settings get secure accessibility_enabled)'
  done
  echo "### dumpsys accessibility"
  tv 'dumpsys accessibility | head -40'
  echo "### logcat"
  tv 'logcat -d -v time | grep -i -E "gathin|FireHome|HomeKeyService|ccessibility|FATAL|AndroidRuntime" | head -80'
} > fireos/activar.txt 2>&1
echo "Listo: fireos/activar.txt. Avísale a Claude."
