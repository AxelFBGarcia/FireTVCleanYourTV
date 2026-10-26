# Código compartido por los scripts de fireos/. Se carga con:  . "$(dirname "$0")/_comun.sh"
# Deja el directorio de trabajo en la raíz del repo y define ROOT, PY, PKG, SVC y las funciones de abajo.
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT=$PWD
: "${TV_HOST:?pon TV_HOST=<ip de la tele>, por ejemplo: TV_HOST=192.168.1.70 bash $0}"
PY=$ROOT/tools/venv/bin/python
[ -x "$PY" ] || { echo "Falta el venv: python3 -m venv tools/venv && tools/venv/bin/pip install -r tools/requirements.txt" >&2; exit 1; }
PKG=com.gathin.tvhome
SVC=$PKG/.HomeKeyService

# Un comando de shell en la tele.
tv() { "$PY" -I "$ROOT/tools/tv.py" "$1"; }

# La actividad al frente. dumpsys es grande y a veces la conexión lo corta ("Broken pipe"), así que se guarda en la
# tele y solo viaja la línea que importa, con reintentos. Vacío si la tele no respondió.
resumed() {
  local r=""
  for _ in 1 2 3; do
    r=$(tv 'dumpsys activity activities > /data/local/tmp/cyt_a.txt 2>/dev/null; grep mResumedActivity /data/local/tmp/cyt_a.txt; rm -f /data/local/tmp/cyt_a.txt' 2>/dev/null | tr -d '\r' || true)
    [ -n "$r" ] && break
    sleep 1
  done
  printf '%s' "$r"
}

# 1 si Android tiene conectado el servicio de Home (escuchando cambios de pantalla), 0 si no.
bound() {
  local n
  n=$(tv 'dumpsys accessibility | grep -c "eventTypes=TYPE_WINDOW_STATE_CHANGED"' 2>/dev/null | tr -dc '0-9' || true)
  [ "${n:-0}" -ge 1 ] && echo 1 || echo 0
}

# Agrega el servicio de Home a la lista sin quitar otros y comprueba que Android lo conectó (3 intentos).
# Ojo: un force-stop de la app lo saca de la lista, así que nada que detenga la app debe ir después de esto.
enable_service() {
  for try in 1 2 3; do
    tv "s=\$(settings get secure enabled_accessibility_services); case \"\$s\" in *$SVC*) ;; null|'') settings put secure enabled_accessibility_services $SVC ;; *) settings put secure enabled_accessibility_services \"\$s:$SVC\" ;; esac; settings put secure accessibility_enabled 1" >/dev/null
    sleep 4
    if [ "$(bound)" = 1 ] && tv 'settings get secure enabled_accessibility_services' | grep -qF "$SVC"; then return 0; fi
    echo "El servicio de Home no quedó conectado (intento $try); reintento." >&2
  done
  return 1
}

# Abre el launcher y espera hasta 10 s a que quede al frente. 0 si quedó, 1 si no.
open_launcher() {
  tv "am start -a android.intent.action.MAIN -c android.intent.category.HOME -n $PKG/.MainActivity" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    sleep 2
    case "$(resumed)" in *"$PKG/.MainActivity"*) return 0 ;; esac
  done
  return 1
}
