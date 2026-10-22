#!/bin/sh
# Runtime only: Python, the MetaTrader5 package and MT5 are already in the image (install-mt5.sh).
set -eu

: "${BRIDGE_TOKEN:?set BRIDGE_TOKEN}"

rm -f /tmp/.X99-lock  # left behind when a previous run of this container died
Xvfb :99 -screen 0 1024x768x16 -nolisten tcp &

# MT5's LiveUpdate opens a "Welcome to LiveUpdate" window when the broker offers a newer build, and
# the terminal then refuses the MetaTrader5 package's IPC until someone closes it. Headless, nobody
# can, so close it here. ponytail: polling every 5 s; one window search is cheap.
(while sleep 5; do
    xdotool search --name "LiveUpdate" windowclose 2>/dev/null || true
done) &

exec wine "$WINEPREFIX/drive_c/Python311/python.exe" 'Z:\opt\bridge\bridge.py'
