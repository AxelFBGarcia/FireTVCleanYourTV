#!/usr/bin/env bash
# Quita el launcher de Fire OS y deja la tele como estaba: el inicio de Amazon vuelve a ser el único.
# Uso, desde la carpeta cleanyourtv:   TV_HOST=192.168.1.70 bash fireos/desinstalar.sh
set -euo pipefail
. "$(dirname "$0")/_comun.sh"
STATE="$HOME/.cleanyourtv/fireos-$(printf '%s' "$TV_HOST" | tr -c 'A-Za-z0-9._-' '_').txt"

# 1. Quitar solo nuestro servicio de accesibilidad.
tv "s=\$(settings get secure enabled_accessibility_services); r=\$(echo \"\$s\" | tr ':' '\n' | grep -v '^$PKG/' | grep -v '^null\$' | grep -v '^\$' | paste -sd: -); if [ -n \"\$r\" ]; then settings put secure enabled_accessibility_services \"\$r\"; else settings delete secure enabled_accessibility_services; settings put secure accessibility_enabled 0; fi; echo servicios=\$(settings get secure enabled_accessibility_services)"

# 2. Regresar alarm_manager_constants a como estaba.
PREV=""
[ -f "$STATE" ] && PREV=$(sed -n 's/^alarm_manager_constants=//p' "$STATE")
if [ -z "$PREV" ] || [ "$PREV" = null ]; then
  tv 'settings delete global alarm_manager_constants >/dev/null; echo alarm_manager_constants=$(settings get global alarm_manager_constants)'
else
  tv "settings put global alarm_manager_constants '$PREV'; echo alarm_manager_constants=\$(settings get global alarm_manager_constants)"
fi

# 3. Desinstalar el launcher (es una app nuestra, no del sistema) y volver al inicio de Amazon.
tv "pm uninstall $PKG"
tv 'input keyevent KEYCODE_HOME' >/dev/null
[ -f "$STATE" ] && mv "$STATE" "$STATE.usado"
echo "Listo: el inicio de Amazon es el único otra vez."
