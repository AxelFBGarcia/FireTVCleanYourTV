#!/usr/bin/env bash
# Graba lo que haces con el control hasta que presiones ENTER, y guarda lo que vio el launcher en fireos/registro.txt
# Uso:   TV_HOST=192.168.1.70 bash fireos/registro.sh
. "$(dirname "$0")/_comun.sh"
tv 'logcat -c' >/dev/null 2>&1
echo ">>> Grabando. Haz la prueba con el control y, cuando termines, presiona ENTER aquí."
read -r _
tv 'logcat -d -v time | grep -E "FireHome|ActivityManager.*(START u0|Displayed)|AndroidRuntime"' > fireos/registro.txt 2>&1
echo "Listo: fireos/registro.txt ($(wc -l < fireos/registro.txt | tr -d ' ') líneas)."
