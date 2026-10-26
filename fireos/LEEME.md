# CleanYourTV en Fire OS (Amazon Fire TV AFTTIFF43)

Launcher de CleanYourTV como inicio en una tele Fire TV, sin root. El inicio de Amazon no se puede
desactivar (paquete protegido), así que se queda instalado y el launcher se pone encima en cuanto aparece.

## Uso (desde la carpeta `cleanyourtv`, con ADB activado en la tele)

| Qué | Comando |
|---|---|
| Instalar / actualizar | `TV_HOST=192.168.1.70 bash fireos/instalar.sh` |
| Quitar todo y volver al inicio de Amazon | `TV_HOST=192.168.1.70 bash fireos/desinstalar.sh` |
| Ver si el servicio de Home está vivo | `TV_HOST=192.168.1.70 bash fireos/estado.sh` |
| Grabar una prueba con el control | `TV_HOST=192.168.1.70 bash fireos/registro.sh` |
| Medir Home → launcher (3 tipos de alarma) | `TV_HOST=192.168.1.70 bash fireos/medir.sh` |
| Revisar una tele nueva antes de instalar (solo lee) | `TV_HOST=192.168.1.70 bash fireos/diagnostico.sh` |

Los scripts comparten `fireos/_comun.sh` (conexión, consulta robusta de la pantalla al frente, activar y
verificar el servicio de Home).

## Dónde está la configuración de Fire TV

En el tipo de compilación `fireos` (`launcher/app/build.gradle`): es el release más
`launcher/app/src/fireos/res/values/config.xml`, cuyos valores reemplazan a los de `src/main/res/values`.
Ahí van el dock, la Appstore, el menú por app y la redirección de Home. `src/main/res/values/config.xml`
se queda como en el repo original, así que traer cambios de `upstream` no choca con esto. Se compila con
`./gradlew assembleFireos` (el instalador ya lo hace). No uses `tools/theme.sh --reset` pensando que
regresa a esta configuración: los temas solo se sobreponen, la de Fire TV vive en el APK.

El estado original de la tele se guarda en `~/.cleanyourtv/fireos-<ip>.txt` en la primera instalación;
`desinstalar.sh` lo usa para dejarla como estaba.

## Cómo funciona

- `FireHome.java` (nuevo): cuando aparece `com.amazon.tv.launcher/.ui.HomeActivity_vNext`, tapa la pantalla
  con una capa negra de accesibilidad y abre el launcher con un `PendingIntent` de actividad disparado por
  `AlarmManager.setExact`. Lo lanza el sistema, así que no le aplica el retraso de ~5 s que Fire OS pone a las
  apps después de Home. Requiere `alarm_manager_constants min_futurity=0` (lo pone el instalador).
- La capa se quita cuando `MainActivity` ya se dibujó (`HomeKeyService.launcherShown`), con tope de 2.5 s.
- Si Amazon reaparece mientras un lanzamiento va en camino, se reintenta. Si el launcher no logra abrirse
  4 veces seguidas, deja el inicio de Amazon en paz 30 s (nunca se queda en negro ni en ciclo).
- `restore_key_services` + `BootRepair.java`: si Fire OS apaga el servicio de accesibilidad (force stop,
  actualización), el launcher lo reactiva al abrirse y al encender la tele (`WRITE_SECURE_SETTINGS` por ADB).
- Botón Menú: abre el menú de la app enfocada; "Mover" mueve una app y al soltarla termina el modo.

## Medición (AFTTIFF43, Fire OS 7.7.1.7 PS7717.6741N), Home → launcher dibujado

| Alarma | Tiempo | Nota |
|---|---|---|
| `exact` (por defecto) | 0.57–0.61 s | lanzamiento en el mismo milisegundo |
| `clock` | 0.53–0.62 s | igual de rápido, registra una alarma de reloj |
| `idle` | 0.49–2.8 s | Android raciona estas alarmas si se repiten seguido |

Para probar otro modo sin recompilar: `settings put global cyt_fire_alarm clock` (borrar el ajuste = `exact`).

## Pendientes conocidos

- Al salir de apps pesadas (Prime Video) la tele queda lenta: el propio inicio de Amazon tarda ~2 s y el
  launcher hasta ~4 s, que se ven en negro.
- Una actualización de Fire OS puede cambiar el nombre de la pantalla de inicio de Amazon o el comportamiento
  de las alarmas; si Home deja de funcionar, correr `estado.sh` y `registro.sh`.
- `min_futurity=0` es un ajuste global: cualquier app puede programar alarmas inmediatas. En una tele no
  tiene efecto práctico; `desinstalar.sh` lo regresa a como estaba.
