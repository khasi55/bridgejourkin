#!/bin/sh
# Runs the bridge on macOS with the MetaTrader 5 app's own Wine. Docker's Wine cannot run the MT5
# terminal on Apple Silicon (it segfaults under Rosetta in the Linux VM); the app's Mac-native Wine
# can. Uses a private copy of the app's Wine prefix (~/mt5-bridge-wine) holding Windows, MT5 and an
# embeddable Python with the MetaTrader5 package, so the MT5 app and anything sharing its prefix
# (MetaTrader 5 Manager) are never touched. Compose roles reach it at host.docker.internal:8765.
set -eu

APP_WINE="/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

export WINEPREFIX="${WINEPREFIX:-$HOME/mt5-bridge-wine}" WINEDEBUG=-all
export WINEDLLOVERRIDES="mscoree,mshtml="
BRIDGE_TOKEN=$(grep -E '^GUARDIAN_SELFHOSTED_BRIDGE_TOKEN=' "$ROOT/.env" | cut -d= -f2-)
: "${BRIDGE_TOKEN:?set GUARDIAN_SELFHOSTED_BRIDGE_TOKEN in .env}"
export BRIDGE_TOKEN BRIDGE_HOST=127.0.0.1 BRIDGE_PORT="${BRIDGE_PORT:-8765}"
export MT5_PATH='C:\Program Files\MetaTrader 5\terminal64.exe'

exec "$APP_WINE" 'C:\Python311\python.exe' "Z:$(printf %s "$ROOT/ops/mt5-bridge/bridge.py" | tr / '\\')"
