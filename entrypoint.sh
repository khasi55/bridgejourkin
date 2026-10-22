#!/bin/sh
# Runtime: Windows Python and the MetaTrader5 package are in the image (install-python.sh); the MT5
# program files come from $MT5_ARCHIVE on the bridge's private volume, unpacked at each start so
# the container itself stays disposable.
set -eu

: "${BRIDGE_TOKEN:?set BRIDGE_TOKEN}"
MT5_ARCHIVE="${MT5_ARCHIVE:-/data/mt5.tar.gz}"
MT5DIR="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"

if [ ! -f "$MT5DIR/terminal64.exe" ]; then
    [ -f "$MT5_ARCHIVE" ] || {
        echo "no MT5 program files: upload a clean MT5 archive to $MT5_ARCHIVE" >&2
        exit 1
    }
    mkdir -p "$MT5DIR"
    tar xzf "$MT5_ARCHIVE" -C "$MT5DIR"
fi

rm -f /tmp/.X99-lock  # left behind when a previous run of this container died
Xvfb :99 -screen 0 1024x768x16 -nolisten tcp &

# MT5's LiveUpdate opens a "Welcome to LiveUpdate" window when the broker offers a newer build, and
# the terminal then refuses the MetaTrader5 package's IPC until someone closes it. Headless, nobody
# can, so close it here. ponytail: polling every 5 s; one window search is cheap.
(while sleep 5; do
    xdotool search --name "LiveUpdate" windowclose 2>/dev/null || true
done) &

exec wine "$WINEPREFIX/drive_c/Python311/python.exe" 'Z:\opt\bridge\bridge.py'
