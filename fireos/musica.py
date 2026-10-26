"""Controla Spotify en la tele desde la laptop, con la Web API oficial (Spotify Connect).

La app de Spotify de la tele reproduce en segundo plano; la tele se queda en el inicio. Solo usa la biblioteca
estándar de Python. Requiere Spotify Premium y una app propia en developer.spotify.com (ver fireos/LEEME.md).

    musica.sh "<link de playlist, álbum, artista, canción o podcast>" [--aleatorio]
    musica.sh pausa | sigue | siguiente | anterior | que
    musica.sh volumen 0-100 | aleatorio si|no | tele | dispositivos | salir

Credenciales y dispositivo elegido: ~/.cleanyourtv/spotify.json (solo lectura para tu usuario).
Con TV_HOST definido y ADB encendido, despierta Spotify en la tele si no aparece y regresa al inicio si se abrió.
"""
import base64
import hashlib
import http.server
import json
import os
import re
import secrets
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path

REDIRECT = "http://127.0.0.1:8888/callback"
SCOPES = "user-read-playback-state user-modify-playback-state"
API = "https://api.spotify.com/v1"
ACCOUNTS = "https://accounts.spotify.com"
CONFIG = Path.home() / ".cleanyourtv" / "spotify.json"
ROOT = Path(__file__).resolve().parent.parent
SPOTIFY_PKG = "com.spotify.tv.android"
SPOTIFY_ACTIVITY = SPOTIFY_PKG + "/.SpotifyTVActivity"

LINK = re.compile(r"(?:https?://open\.spotify\.com/(?:intl-[a-z-]+/)?|spotify:)"
                  r"(playlist|album|artist|show|track|episode)[/:]([A-Za-z0-9]{22})")
CONTEXT_TYPES = {"playlist", "album", "artist", "show"}


class Problema(Exception):
    """Un error que se le explica al usuario tal cual, sin traceback."""


# ---------- configuración ----------

def load():
    try:
        return json.loads(CONFIG.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}


def save(cfg):
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    tmp = CONFIG.with_suffix(".tmp")
    tmp.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    os.chmod(tmp, stat.S_IRUSR | stat.S_IWUSR)
    tmp.replace(CONFIG)


# ---------- enlaces ----------

def parse_link(text):
    """('context_uri'|'uris', uri) para un link de open.spotify.com o una URI spotify:, o None."""
    m = LINK.search(text.strip())
    if not m:
        return None
    kind, ident = m.group(1), m.group(2)
    uri = f"spotify:{kind}:{ident}"
    return ("context_uri", uri) if kind in CONTEXT_TYPES else ("uris", uri)


# ---------- OAuth (Authorization Code con PKCE: no hace falta client secret) ----------

def post_form(url, data):
    req = urllib.request.Request(url, data=urllib.parse.urlencode(data).encode(),
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise Problema(f"Spotify rechazó el inicio de sesión ({e.code}): {e.read().decode(errors='replace')}")


def store_token(cfg, tok):
    cfg["access_token"] = tok["access_token"]
    cfg["expires_at"] = time.time() + int(tok.get("expires_in", 3600)) - 60
    if tok.get("refresh_token"):
        cfg["refresh_token"] = tok["refresh_token"]
    save(cfg)


def login(cfg):
    if not cfg.get("client_id"):
        print("Primera vez: pega el Client ID de tu app de developer.spotify.com (ver fireos/LEEME.md).")
        cfg["client_id"] = input("Client ID: ").strip()
        if not re.fullmatch(r"[0-9a-f]{32}", cfg["client_id"]):
            raise Problema("Eso no parece un Client ID (son 32 caracteres hexadecimales).")
        save(cfg)
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
    state = secrets.token_urlsafe(16)
    url = ACCOUNTS + "/authorize?" + urllib.parse.urlencode({
        "client_id": cfg["client_id"], "response_type": "code", "redirect_uri": REDIRECT,
        "code_challenge_method": "S256", "code_challenge": challenge, "scope": SCOPES, "state": state})
    got = {}

    class Callback(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            got.update({k: v[0] for k, v in q.items()})
            ok = "code" in got and got.get("state") == state
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            msg = "Listo, ya puedes cerrar esta pestaña." if ok else "No se pudo iniciar sesión; revisa la Terminal."
            self.wfile.write(f"<html><body style='font-family:sans-serif'><h2>{msg}</h2></body></html>".encode())

        def log_message(self, *args):
            pass

    try:
        server = http.server.HTTPServer(("127.0.0.1", 8888), Callback)
    except OSError:
        raise Problema("El puerto 8888 está ocupado; cierra lo que lo use e inténtalo otra vez.")
    server.timeout = 300
    print("Se abrirá el navegador para que autorices la app en Spotify (una sola vez)...")
    if not webbrowser.open(url):
        print("Abre este enlace en el navegador:\n" + url)
    server.handle_request()
    server.server_close()
    if got.get("state") != state or "code" not in got:
        raise Problema("No se completó la autorización: " + got.get("error", "sin respuesta en 5 minutos"))
    store_token(cfg, post_form(ACCOUNTS + "/api/token", {
        "grant_type": "authorization_code", "code": got["code"], "redirect_uri": REDIRECT,
        "client_id": cfg["client_id"], "code_verifier": verifier}))
    print("Sesión iniciada; queda guardada en " + str(CONFIG))


def token(cfg, force=False):
    if not cfg.get("refresh_token"):
        login(cfg)
    elif force or time.time() >= cfg.get("expires_at", 0):
        store_token(cfg, post_form(ACCOUNTS + "/api/token", {
            "grant_type": "refresh_token", "refresh_token": cfg["refresh_token"], "client_id": cfg["client_id"]}))
    return cfg["access_token"]


# ---------- Web API ----------

def api(cfg, method, path, params=None, body=None, _retry=True):
    """(status, json o None). Renueva el token una vez ante 401 y espera ante 429."""
    url = API + path + ("?" + urllib.parse.urlencode(params) if params else "")
    data = json.dumps(body).encode() if body is not None else (b"" if method in ("PUT", "POST") else None)
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bearer " + token(cfg), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        if e.code == 401 and _retry:
            token(cfg, force=True)
            return api(cfg, method, path, params, body, _retry=False)
        if e.code == 429 and _retry:
            time.sleep(min(int(e.headers.get("Retry-After", "2")), 30))
            return api(cfg, method, path, params, body, _retry=False)
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, {"error": {"message": raw.decode(errors="replace")}}
    except urllib.error.URLError as e:
        raise Problema(f"No hay conexión con Spotify: {e.reason}")


def error_text(status, data):
    err = (data or {}).get("error", {})
    reason = err.get("reason", "") if isinstance(err, dict) else ""
    message = err.get("message", "") if isinstance(err, dict) else str(err)
    if reason == "PREMIUM_REQUIRED" or status == 403 and "premium" in message.lower():
        return "Spotify pide Premium para controlar la reproducción."
    if reason == "VOLUME_CONTROL_DISALLOW":
        return "La app de Spotify de la tele no deja cambiar el volumen por Connect; usa el control de la tele."
    return f"Spotify respondió {status}: {message or reason or 'sin detalle'}"


def devices(cfg):
    status, data = api(cfg, "GET", "/me/player/devices")
    if status != 200:
        raise Problema(error_text(status, data))
    return data.get("devices", [])


def pick_tv(cfg, choose=False):
    """El dispositivo de la tele: el guardado (por id o nombre), o se elige y se guarda."""
    found = devices(cfg)
    if not choose:
        for d in found:
            if d.get("id") == cfg.get("device_id") or d.get("name") == cfg.get("device_name"):
                if d.get("id") != cfg.get("device_id"):
                    cfg["device_id"] = d["id"]
                    save(cfg)
                return d
        if cfg.get("device_name"):
            return None
    tvs = [d for d in found if d.get("type", "").lower() in ("tv", "castvideo", "stb")] or found
    if not tvs:
        return None
    if len(tvs) == 1 and not choose:
        chosen = tvs[0]
    else:
        for i, d in enumerate(tvs, 1):
            print(f"  {i}. {d.get('name')} ({d.get('type')})")
        n = input("¿Cuál es la tele? Número: ").strip()
        if not n.isdigit() or not 1 <= int(n) <= len(tvs):
            raise Problema("Número no válido.")
        chosen = tvs[int(n) - 1]
    cfg["device_id"], cfg["device_name"] = chosen["id"], chosen.get("name", "")
    save(cfg)
    print(f"Tele guardada: {cfg['device_name']}")
    return chosen


# ---------- ADB (opcional) ----------

def adb(command):
    """Salida de un comando en la tele, o None si no hay TV_HOST o ADB no responde."""
    if not os.environ.get("TV_HOST"):
        return None
    try:
        r = subprocess.run([sys.executable, "-I", str(ROOT / "tools" / "tv.py"), command],
                           capture_output=True, text=True, timeout=25)
        return r.stdout if r.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def wake_tv(cfg):
    """Spotify no está activo en la tele: lo abre por ADB y espera a que aparezca como dispositivo."""
    if adb(f"am start -n {SPOTIFY_ACTIVITY}") is None:
        raise Problema("La tele no aparece en Spotify. Abre Spotify una vez en la tele (o enciende ADB y pon "
                       "TV_HOST=<ip> para que lo abra el script) e inténtalo otra vez.")
    print("Despertando Spotify en la tele...")
    for _ in range(12):
        time.sleep(2)
        d = pick_tv(cfg)
        if d:
            return d
    raise Problema("Spotify se abrió en la tele pero no apareció como dispositivo; espera unos segundos y repite.")


def back_home():
    """Si Spotify quedó al frente, Home: FireHome lleva al inicio de CleanYourTV."""
    front = adb("dumpsys activity activities > /data/local/tmp/cyt_a.txt 2>/dev/null; "
                "grep mResumedActivity /data/local/tmp/cyt_a.txt; rm -f /data/local/tmp/cyt_a.txt")
    if front and SPOTIFY_PKG in front:
        adb("input keyevent KEYCODE_HOME")


# ---------- órdenes ----------

def tv_device(cfg):
    d = pick_tv(cfg)
    return d if d else wake_tv(cfg)


def control(cfg, method, path, params=None, body=None, ok_msg=""):
    d = tv_device(cfg)
    status, data = api(cfg, method, path, dict(params or {}, device_id=d["id"]), body)
    if status not in (200, 202, 204):
        raise Problema(error_text(status, data))
    if ok_msg:
        print(ok_msg)


def play(cfg, link, shuffle):
    key, uri = link
    d = tv_device(cfg)
    body = {key: uri} if key == "context_uri" else {key: [uri]}
    status, data = api(cfg, "PUT", "/me/player/play", {"device_id": d["id"]}, body)
    if status == 404:   # la tele dejó de estar activa entre la consulta y la orden
        d = wake_tv(cfg)
        status, data = api(cfg, "PUT", "/me/player/play", {"device_id": d["id"]}, body)
    if status not in (200, 202, 204):
        raise Problema(error_text(status, data))
    if shuffle:
        api(cfg, "PUT", "/me/player/shuffle", {"state": "true", "device_id": d["id"]})
    print(f"Sonando en {d.get('name')}: {uri}")
    time.sleep(3)
    back_home()


def now_playing(cfg):
    status, data = api(cfg, "GET", "/me/player")
    if status == 204 or not data:
        print("No hay nada sonando.")
        return
    if status != 200:
        raise Problema(error_text(status, data))
    item = data.get("item") or {}
    artists = ", ".join(a.get("name", "") for a in item.get("artists", []))
    where = (data.get("device") or {}).get("name", "?")
    state = "sonando" if data.get("is_playing") else "en pausa"
    vol = (data.get("device") or {}).get("volume_percent")
    print(f"{item.get('name', '?')}{' — ' + artists if artists else ''}  [{state} en {where}"
          f"{f', volumen {vol}%' if vol is not None else ''}]")


def main(argv):
    if not argv or argv[0] in ("-h", "--help", "ayuda"):
        print(__doc__)
        return 0
    cfg = load()
    cmd, rest = argv[0].lower(), argv[1:]
    link = parse_link(argv[0])
    if link:
        play(cfg, link, shuffle="--aleatorio" in rest)
    elif cmd == "pausa":
        control(cfg, "PUT", "/me/player/pause", ok_msg="En pausa.")
    elif cmd in ("sigue", "play", "continua", "continúa"):
        control(cfg, "PUT", "/me/player/play", ok_msg="Sonando.")
    elif cmd == "siguiente":
        control(cfg, "POST", "/me/player/next", ok_msg="Siguiente.")
    elif cmd == "anterior":
        control(cfg, "POST", "/me/player/previous", ok_msg="Anterior.")
    elif cmd == "volumen":
        if not rest or not rest[0].isdigit() or not 0 <= int(rest[0]) <= 100:
            raise Problema("Uso: musica.sh volumen 0-100")
        control(cfg, "PUT", "/me/player/volume", {"volume_percent": rest[0]}, ok_msg=f"Volumen {rest[0]}%.")
    elif cmd == "aleatorio":
        on = bool(rest) and rest[0].lower() in ("si", "sí", "on", "1")
        control(cfg, "PUT", "/me/player/shuffle", {"state": str(on).lower()},
                ok_msg="Aleatorio " + ("activado." if on else "desactivado."))
    elif cmd == "que":
        now_playing(cfg)
    elif cmd == "tele":
        if not pick_tv(cfg, choose=True):
            raise Problema("Spotify no ve ningún dispositivo; abre Spotify en la tele y repite.")
    elif cmd == "dispositivos":
        for d in devices(cfg):
            mark = " (activo)" if d.get("is_active") else ""
            print(f"  {d.get('name')} [{d.get('type')}]{mark}")
    elif cmd == "salir":
        CONFIG.unlink(missing_ok=True)
        print("Sesión borrada. Para quitar el acceso también: spotify.com → Cuenta → Apps → quitar acceso.")
    else:
        raise Problema(f"No entendí '{argv[0]}'. Usa un link de Spotify o: pausa, sigue, siguiente, anterior, "
                       "volumen N, aleatorio si|no, que, tele, dispositivos, salir.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Problema as p:
        print(p, file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
