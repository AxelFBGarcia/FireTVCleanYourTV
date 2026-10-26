#!/usr/bin/env bash
# Fire OS: compila el launcher de CleanYourTV con el atajo rápido de Home (FireHome) y lo instala en la tele.
# El inicio de Amazon NO se desactiva ni se desinstala (Fire OS no lo permite): el launcher se pone encima.
# Deshacer: TV_HOST=<ip> bash fireos/desinstalar.sh
#
# Uso, desde la carpeta cleanyourtv:   TV_HOST=192.168.1.70 bash fireos/instalar.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
: "${TV_HOST:?pon TV_HOST=<ip de la tele>}"
PY=$ROOT/tools/venv/bin/python
[ -x "$PY" ] || { echo "Falta el venv: python3 -m venv tools/venv && tools/venv/bin/pip install -r tools/requirements.txt" >&2; exit 1; }
tv() { "$PY" -I "$ROOT/tools/tv.py" "$1"; }
resumed() {   # dumpsys es grande: se guarda en la tele y solo viaja la línea que importa, con reintentos.
  local r=""
  for _ in 1 2 3; do
    r=$(tools/venv/bin/python -I tools/tv.py 'dumpsys activity activities > /data/local/tmp/cyt_a.txt 2>/dev/null; grep mResumedActivity /data/local/tmp/cyt_a.txt; rm -f /data/local/tmp/cyt_a.txt' 2>/dev/null | tr -d '\r' || true)
    [ -n "$r" ] && break; sleep 1
  done
  printf '%s' "$r"
}
PKG=com.gathin.tvhome
SVC=$PKG/.HomeKeyService

echo "== 1/6 Revisando la tele"
MODEL=$(tv 'getprop ro.product.model' | tr -d '\r\n')
SDK=$(tv 'getprop ro.build.version.sdk' | tr -dc '0-9')
echo "Modelo $MODEL, SDK $SDK"
if [ "$MODEL" != AFTTIFF43 ] && [ "${FORCE:-0}" != 1 ]; then
  echo "Esto se probó para AFTTIFF43; esta tele es $MODEL. FORCE=1 para seguir de todos modos." >&2; exit 1
fi
[ "$SDK" -ge 26 ] || { echo "El launcher necesita Android 8 o más nuevo (SDK 26); esta tele tiene SDK $SDK." >&2; exit 1; }

echo "== 2/6 Buscando Java y el SDK de Android"
# El Gradle del launcher necesita JDK 17 o más nuevo. Ojo: en macOS `java_home -v 17` devuelve el JDK por
# defecto (aquí un 11) cuando no hay 17, así que se revisa la versión real de cada candidato.
java_major() { "$1/bin/java" -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -n 1; }
if [ -n "${JAVA_HOME:-}" ] && [ "$(java_major "$JAVA_HOME")" -lt 17 ] 2>/dev/null; then
  echo "JAVA_HOME apunta a Java $(java_major "$JAVA_HOME"); busco uno 17+ para compilar."; JAVA_HOME=""
fi
if [ -z "${JAVA_HOME:-}" ]; then
  for j in "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
           /opt/homebrew/opt/openjdk@21 /opt/homebrew/opt/openjdk@17 \
           "$(/usr/libexec/java_home -v 17 2>/dev/null || true)"; do
    [ -n "$j" ] && [ -x "$j/bin/java" ] && [ -x "$j/bin/jlink" ] || continue
    v=$(java_major "$j"); [ -n "$v" ] && [ "$v" -ge 17 ] || continue
    JAVA_HOME=$j; break
  done
fi
[ -n "${JAVA_HOME:-}" ] || { echo "No encontré un JDK 17+ (instala Android Studio o: brew install openjdk@17)." >&2; exit 1; }
export JAVA_HOME PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
[ -d "$ANDROID_HOME" ] || { echo "No encontré el SDK de Android en $ANDROID_HOME (ábrelo una vez en Android Studio)." >&2; exit 1; }
echo "JAVA_HOME=$JAVA_HOME"; echo "ANDROID_HOME=$ANDROID_HOME"

echo "== 3/6 Pruebas y compilación (la primera vez tarda unos minutos)"
cd "$ROOT/launcher"
[ -f local.properties ] || echo "sdk.dir=$ANDROID_HOME" > local.properties
# El launcher compila contra Android 34; tu SDK solo tiene 36.1. Gradle baja la plataforma 34 y build-tools 34
# solo si las licencias están aceptadas (ya lo están en tu SDK). Si se queja de licencias:
#   yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses
./gradlew -q --console=plain testDebugUnitTest --tests 'com.gathin.tvhome.FireHomeTest' --tests 'com.gathin.tvhome.HomeKeyServiceTest'
./gradlew -q --console=plain assembleRelease
APK=$ROOT/launcher/app/build/outputs/apk/release/app-release.apk
ls -lh "$APK"
cd "$ROOT"

echo "== 4/6 Guardando el estado actual (para deshacer)"
mkdir -p "$HOME/.cleanyourtv"
STATE="$HOME/.cleanyourtv/fireos-$(printf '%s' "$TV_HOST" | tr -c 'A-Za-z0-9._-' '_').txt"
if [ ! -f "$STATE" ]; then
  {
    echo "alarm_manager_constants=$(tv 'settings get global alarm_manager_constants' | tr -d '\r\n')"
    echo "enabled_accessibility_services=$(tv 'settings get secure enabled_accessibility_services' | tr -d '\r\n')"
    echo "accessibility_enabled=$(tv 'settings get secure accessibility_enabled' | tr -d '\r\n')"
  } > "$STATE"
  echo "Guardado en $STATE"
else
  echo "Ya existe $STATE (de una instalación anterior); se conserva el original."
fi
cat "$STATE"

echo "== 5/6 Instalando"
"$PY" -I tools/b64push.py "$APK" /data/local/tmp/tvhome.apk
OUT=$(tv 'pm install -r /data/local/tmp/tvhome.apk; rm -f /data/local/tmp/tvhome.apk')
echo "$OUT"
case "$OUT" in *Success*) ;; *) echo "La instalación falló; no se cambió nada más." >&2; exit 1 ;; esac
# compile -f detiene la app, y Android quita el servicio de accesibilidad de cualquier app detenida a la fuerza.
# Por eso todo lo que detiene la app va ANTES de activar el servicio (paso 6), nunca después.
printf '%s\n' \
  "pm grant $PKG android.permission.ACCESS_FINE_LOCATION 2>/dev/null; echo ubicacion-para-nombre-wifi" \
  "pm grant $PKG android.permission.WRITE_SECURE_SETTINGS && echo permiso-para-reactivar-su-servicio" \
  "cmd package compile -m speed -f $PKG" \
  | "$PY" -I tools/tv.py --batch
tv "am force-stop $PKG" >/dev/null
# Sin -W: esperar el arranque dentro de la misma conexión a veces corta el canal ("Broken pipe") aunque la app sí
# arranque. Se lanza y luego se pregunta, hasta 10 s, qué actividad quedó al frente.
tv "am start -a android.intent.action.MAIN -c android.intent.category.HOME -n $PKG/.MainActivity" || true
UP=""
for _ in 1 2 3 4 5; do
  sleep 2
  NOW=$(resumed)
  case "$NOW" in *"$PKG/.MainActivity"*) UP=1; break ;; esac
done
echo "${NOW:-sin respuesta}"
[ -n "$UP" ] || { echo "El launcher no quedó al frente; no se activó el atajo de Home. El inicio de Amazon sigue normal." >&2; exit 1; }

echo "== 6/6 Activando el atajo de Home"
# min_futurity=0: sin esto Android 9 retrasa la alarma ~5 s y el truco no sirve. Se conserva lo que ya hubiera.
tv 'c=$(settings get global alarm_manager_constants); case "$c" in null|"") settings put global alarm_manager_constants min_futurity=0 ;; *min_futurity=0*) ;; *) settings put global alarm_manager_constants "$c,min_futurity=0" ;; esac; echo alarm_manager_constants=$(settings get global alarm_manager_constants)'
# Se agrega el servicio sin quitar otros que ya estuvieran activos, y se comprueba que Android lo conectó.
enable_svc() {
  tv "s=\$(settings get secure enabled_accessibility_services); case \"\$s\" in *$SVC*) ;; null|'') settings put secure enabled_accessibility_services $SVC ;; *) settings put secure enabled_accessibility_services \"\$s:$SVC\" ;; esac; settings put secure accessibility_enabled 1; echo servicios=\$(settings get secure enabled_accessibility_services)"
}
bound() { tv 'dumpsys accessibility | grep -c "eventTypes=TYPE_WINDOW_STATE_CHANGED"' 2>/dev/null | tr -dc '0-9'; }
OK=""
for try in 1 2 3; do
  enable_svc
  sleep 4
  if [ "$(bound)" -ge 1 ] 2>/dev/null && tv 'settings get secure enabled_accessibility_services' | grep -qF "$SVC"; then OK=1; break; fi
  echo "El servicio no quedó conectado (intento $try); reintento."
done
[ -n "$OK" ] || { echo "No se pudo conectar el servicio de Home. Corre: TV_HOST=$TV_HOST bash fireos/activar.sh y pásale fireos/activar.txt a Claude." >&2; exit 1; }
echo "Servicio de Home conectado."
tv 'input keyevent KEYCODE_HOME' >/dev/null
sleep 3
NOW=$(resumed)
echo "$NOW"
case "$NOW" in
  *"$PKG"*) echo "LISTO: el botón Home ya abre CleanYourTV. Prueba con el control remoto." ;;
  *) echo "AVISO: después de Home quedó otra pantalla. Pásale a Claude la salida y fireos/log.txt:"
     tv 'logcat -d -t 300 | grep -E "FireHome|HomeKeyService|AlarmManager|ActivityManager: START" ' > fireos/log.txt 2>&1 || true ;;
esac
echo "Deshacer en cualquier momento: TV_HOST=$TV_HOST bash fireos/desinstalar.sh"
