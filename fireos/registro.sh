#!/usr/bin/env bash
# Graba lo que haces con el control hasta que presiones ENTER, y guarda lo que vio el launcher en fireos/registro.txt
# Uso:   TV_HOST=192.168.1.70 bash fireos/registro.sh
cd "$(dirname "$0")/.." || exit 1
: "${TV_HOST:?pon TV_HOST=<ip de la tele>}"
tv() { tools/venv/bin/python -I tools/tv.py "$1" 2>&1; }
tv 'logcat -c' >/dev/null
echo ">>> Grabando. Haz la prueba con el control y, cuando termines, presiona ENTER aquí."
read -r _
tv 'logcat -d -v time | grep -E "TvHomeMenu|FireHome|ActivityManager.*(START u0|Displayed)|AndroidRuntime"' > fireos/registro.txt
echo "Listo: fireos/registro.txt ($(wc -l < fireos/registro.txt) líneas). Avísale a Claude."
