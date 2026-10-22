#!/bin/sh
# Runtime: Windows Python and the MetaTrader5 package are in the image (install-python.sh); the MT5
# program files come from $MT5_ARCHIVE on the bridge's private volume, unpacked at each start so
# the container itself stays disposable.
set -eu

: "${BRIDGE_TOKEN:?set BRIDGE_TOKEN}"
MT5_ARCHIVE="${MT5_ARCHIVE:-/data/mt5.tar.gz}"
MT5DIR="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"

# Unpack MT5 in the background: the bridge must answer /health right away, or the host's health
# check fails the deploy, and Railway can only upload the archive into a running, healthy
# container. MT5 is needed only at the first login, which fails clearly until it is here.
(until [ -f "$MT5DIR/terminal64.exe" ]; do
    if [ -f "$MT5_ARCHIVE" ]; then
        sleep 5  # let an upload in progress finish writing
        mkdir -p "$MT5DIR" && tar xzf "$MT5_ARCHIVE" -C "$MT5DIR" && echo "MT5 unpacked" >&2
    else
        echo "waiting for a clean MT5 archive at $MT5_ARCHIVE" >&2
        sleep 30
    fi
done) &

rm -f /tmp/.X99-lock  # left behind when a previous run of this container died
Xvfb :99 -screen 0 1024x768x16 -nolisten tcp &

# MT5's LiveUpdate opens a "Welcome to LiveUpdate" window when the broker offers a newer build, and
# the terminal then refuses the MetaTrader5 package's IPC until someone closes it. Headless, nobody
# can, so close it here. ponytail: polling every 5 s; one window search is cheap.
(while sleep 5; do
    xdotool search --name "LiveUpdate" windowclose 2>/dev/null || true
done) &

exec wine "$WINEPREFIX/drive_c/Python311/python.exe" 'Z:\opt\bridge\bridge.py'
