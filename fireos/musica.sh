#!/usr/bin/env bash
# Spotify en la tele desde la laptop. Ver fireos/musica.py o: bash fireos/musica.sh ayuda
cd "$(dirname "$0")/.." || exit 1
PY=tools/venv/bin/python
[ -x "$PY" ] || PY=python3
exec "$PY" -I fireos/musica.py "$@"
