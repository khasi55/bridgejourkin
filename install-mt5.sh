#!/bin/sh
# Installs Windows Python, the MetaTrader5 package and MT5 (MetaQuotes' official installer) into
# $WINEPREFIX. The CI workflow runs it in a plain `docker run` on an x86 runner and commits the
# container as the image: Railway's sandbox cannot run the installer (it trips MT5's debugger
# check), and BuildKit's build sandbox may not either.
set -eu

PYTHON_VERSION=3.11.9
MT5_PACKAGE=MetaTrader5==5.0.6231
PYDIR="$WINEPREFIX/drive_c/Python311"
MT5DIR="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"

step() { echo "== $(date -u +%H:%M:%S) $*"; }

Xvfb :99 -screen 0 1024x768x16 -nolisten tcp &
xvfb=$!

step "wine prefix"
wineboot --init
wineserver -w

step "python $PYTHON_VERSION (embeddable; the installer's bootstrapper is 32-bit)"
curl -fsSL -o /tmp/python.zip \
    "https://www.python.org/ftp/python/$PYTHON_VERSION/python-$PYTHON_VERSION-embed-amd64.zip"
mkdir -p "$PYDIR"
unzip -q /tmp/python.zip -d "$PYDIR"
sed -i 's/^#import site/import site/' "$PYDIR/python311._pth"
curl -fsSL -o /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py
wine "$PYDIR/python.exe" 'Z:\tmp\get-pip.py' --quiet --no-warn-script-location
wine "$PYDIR/python.exe" -m pip install --quiet --disable-pip-version-check \
    --no-warn-script-location "$MT5_PACKAGE"
wine "$PYDIR/python.exe" -c "import MetaTrader5 as m; print('MetaTrader5', m.__version__)"

step "mt5 (official installer)"
curl -fsSL -o /tmp/mt5setup.exe \
    https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe
touch /tmp/install-start
wine /tmp/mt5setup.exe /auto &

# The installer downloads the terminal, then starts it; wait for the files, not for exit.
installing() { grep -qa mt5setup /proc/[0-9]*/cmdline 2>/dev/null; }
i=0
while [ $i -lt 120 ]; do
    [ -f "$MT5DIR/terminal64.exe" ] && ! installing && break
    [ $((i % 12)) -eq 0 ] && step "waiting: installer running=$(installing && echo yes || echo no)"
    i=$((i + 1))
    sleep 5
done

if [ ! -f "$MT5DIR/terminal64.exe" ]; then
    step "MT5 install failed; evidence follows"
    echo "windows:"
    xdotool search --onlyvisible --name "." 2>/dev/null | while read -r w; do
        echo "  $(xdotool getwindowname "$w" 2>/dev/null)"
    done
    echo "files the installer wrote:"
    find "$WINEPREFIX/drive_c" -newer /tmp/install-start -type f 2>/dev/null | head -40
    xwd -root -silent | xwdtopnm 2>/dev/null | pnmtopng > /tmp/install-failed.png || true
    exit 1
fi

sleep 10  # let the first terminal start finish writing its files
wineserver -k || true
kill "$xvfb" || true

# Ship the program only: no logs, caches, first-run config or chart layouts.
rm -rf "$MT5DIR/logs" "$MT5DIR/temp" "$MT5DIR/config" "$MT5DIR/Bases" "$MT5DIR/bases" \
    "$MT5DIR/MQL5/Logs" "$MT5DIR/MQL5/Profiles/Charts"
rm -f /tmp/python.zip /tmp/get-pip.py /tmp/mt5setup.exe /tmp/install-start /tmp/.X99-lock
step "installed: $(ls "$MT5DIR" | tr '\n' ' ')"
