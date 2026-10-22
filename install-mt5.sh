#!/bin/sh
# Image build step: Windows Python, the MetaTrader5 package and MT5 from MetaQuotes' official
# installer, all into $WINEPREFIX. Runs on a plain x86 Docker host (CI). Railway's sandbox cannot
# run it: MT5's installer and LiveUpdate mistake the sandbox for a debugger and stop.
set -eu

PYTHON_VERSION=3.11.9
MT5_PACKAGE=MetaTrader5==5.0.6231
PYDIR="$WINEPREFIX/drive_c/Python311"
MT5DIR="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"

Xvfb :99 -screen 0 1024x768x16 -nolisten tcp &
xvfb=$!

wineboot --init
wineserver -w

# The embeddable zip, not the installer: the installer's bootstrapper is a 32-bit program and this
# image runs 64-bit code only (see the Dockerfile).
curl -fsSL -o /tmp/python.zip \
    "https://www.python.org/ftp/python/$PYTHON_VERSION/python-$PYTHON_VERSION-embed-amd64.zip"
mkdir -p "$PYDIR"
unzip -q /tmp/python.zip -d "$PYDIR"
sed -i 's/^#import site/import site/' "$PYDIR/python311._pth"
curl -fsSL -o /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py
wine "$PYDIR/python.exe" 'Z:\tmp\get-pip.py' --quiet --no-warn-script-location
wine "$PYDIR/python.exe" -m pip install --quiet --disable-pip-version-check \
    --no-warn-script-location "$MT5_PACKAGE"

curl -fsSL -o /tmp/mt5setup.exe \
    https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe
wine /tmp/mt5setup.exe /auto &

# The installer downloads the terminal, then starts it; wait for the files, not for exit.
installing() { grep -qa mt5setup /proc/[0-9]*/cmdline 2>/dev/null; }
i=0
while [ $i -lt 120 ]; do
    [ -f "$MT5DIR/terminal64.exe" ] && ! installing && break
    i=$((i + 1))
    sleep 5
done
sleep 10  # let the first terminal start finish writing its files
wineserver -k || true
kill "$xvfb" || true
[ -f "$MT5DIR/terminal64.exe" ] || { echo "MT5 install failed" >&2; exit 1; }

# Ship the program only: no logs, caches, first-run config or chart layouts.
rm -rf "$MT5DIR/logs" "$MT5DIR/temp" "$MT5DIR/config" "$MT5DIR/Bases" "$MT5DIR/bases" \
    "$MT5DIR/MQL5/Logs" "$MT5DIR/MQL5/Profiles/Charts"
rm -f /tmp/python.zip /tmp/get-pip.py /tmp/mt5setup.exe
echo "installed: $(ls "$MT5DIR" | tr '\n' ' ')"
