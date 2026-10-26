#!/usr/bin/env bash
# 1) Comprueba que el launcher arranca sin tronar.  2) Conecta el servicio de Home y verifica que quedó vivo.
# 3) Mide Home -> CleanYourTV con cada tipo de alarma (idle, exact, clock), 3 veces, pulsando Home por software.
# Resultados en fireos/medir.txt.   Uso:   TV_HOST=192.168.1.70 bash fireos/medir.sh
cd "$(dirname "$0")/.." || exit 1
: "${TV_HOST:?pon TV_HOST=<ip de la tele>}"
tv() { tools/venv/bin/python -I tools/tv.py "$1" 2>&1; }
PKG=com.gathin.tvhome
SVC=$PKG/.HomeKeyService
OUT=fireos/medir.txt
resumed() {   # dumpsys es grande: se guarda en la tele y solo viaja la línea que importa, con reintentos.
  local r=""
  for _ in 1 2 3; do
    r=$(tools/venv/bin/python -I tools/tv.py 'dumpsys activity activities > /data/local/tmp/cyt_a.txt 2>/dev/null; grep mResumedActivity /data/local/tmp/cyt_a.txt; rm -f /data/local/tmp/cyt_a.txt' 2>/dev/null | tr -d '\r' || true)
    [ -n "$r" ] && break; sleep 1
  done
  printf '%s' "$r"
}
bound() { tv 'dumpsys accessibility | grep -c "eventTypes=TYPE_WINDOW_STATE_CHANGED"' | tr -dc '0-9'; }
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
for try in 1 2 3; do
  tv "s=\$(settings get secure enabled_accessibility_services); case \"\$s\" in *$SVC*) ;; null|'') settings put secure enabled_accessibility_services $SVC ;; *) settings put secure enabled_accessibility_services \"\$s:$SVC\" ;; esac; settings put secure accessibility_enabled 1" >> "$OUT"
  sleep 4
  [ "$(bound)" -ge 1 ] 2>/dev/null && break
done
echo "bound=$(bound) servicios=$(tv 'settings get secure enabled_accessibility_services')" >> "$OUT"
[ "$(bound)" -ge 1 ] 2>/dev/null || { echo "2/3 El servicio no se conectó. Pásale fireos/medir.txt a Claude."; exit 1; }
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
    echo "### $mode #$rep (bound=$(bound))" >> "$OUT"
    tv 'logcat -d -v time | grep -E "FireHome|ActivityManager.*(START u0|Displayed)"' >> "$OUT"
    echo "   $mode #$rep listo"
  done
done
tv "settings delete global cyt_fire_alarm" >/dev/null
tv "am start -a android.intent.action.MAIN -c android.intent.category.HOME -n $PKG/.MainActivity" >/dev/null
echo "3/3 Listo: $OUT. Avísale a Claude."
