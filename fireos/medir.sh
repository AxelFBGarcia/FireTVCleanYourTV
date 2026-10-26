#!/usr/bin/env bash
# 1) Comprueba que el launcher arranca sin tronar.  2) Conecta el servicio de Home y verifica que quedó vivo.
# 3) Mide Home -> CleanYourTV con cada tipo de alarma (idle, exact, clock), 3 veces, pulsando Home por software.
# Resultados en fireos/medir.txt.   Uso:   TV_HOST=192.168.1.70 bash fireos/medir.sh
. "$(dirname "$0")/_comun.sh"
OUT=fireos/medir.txt
{
  echo "## 1. Arranque"
  tv 'logcat -b crash -c; logcat -c'
  tv "am start -a android.intent.action.MAIN -c android.intent.category.HOME -n $PKG/.MainActivity"
  sleep 4
  NOW=$(resumed); echo "resumed: $NOW"
  echo "--- crash buffer:"; tv 'logcat -b crash -d | tail -40'
  echo "--- errores del launcher:"; tv 'logcat -d -v time | grep -E "AndroidRuntime|gathin" | tail -30'
} > "$OUT"
case "$NOW" in
  *"$PKG/.MainActivity"*) echo "1/3 El launcher arranca bien." ;;
  *) echo "1/3 El launcher NO quedó al frente. Revisa fireos/medir.txt (o pásaselo a Claude)."; exit 1 ;;
esac

echo "## 2. Servicio" >> "$OUT"
enable_service 2>> "$OUT" || { echo "2/3 El servicio no se conectó. Revisa fireos/medir.txt."; exit 1; }
echo "2/3 Servicio de Home conectado."

echo "## 3. Medición" >> "$OUT"
for mode in idle exact clock; do
  tv "settings put global cyt_fire_alarm $mode" >/dev/null
  for rep in 1 2 3; do
    tv "am start -a android.intent.action.MAIN -c android.intent.category.HOME -n $PKG/.MainActivity" >/dev/null
    sleep 3
    tv 'logcat -c' >/dev/null
    tv 'input keyevent KEYCODE_HOME' >/dev/null
    sleep 5
    echo "### $mode #$rep (servicio=$(bound))" >> "$OUT"
    tv 'logcat -d -v time | grep -E "FireHome|ActivityManager.*(START u0|Displayed)"' >> "$OUT"
    echo "   $mode #$rep listo"
  done
done
tv "settings delete global cyt_fire_alarm" >/dev/null
tv "am start -a android.intent.action.MAIN -c android.intent.category.HOME -n $PKG/.MainActivity" >/dev/null
echo "3/3 Listo: $OUT. Avísale a Claude."
