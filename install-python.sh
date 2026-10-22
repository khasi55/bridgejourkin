#!/bin/sh
# Installs Windows Python and the MetaTrader5 package into $WINEPREFIX. The CI workflow runs it in
# a plain container and commits the result as the image.
#
# MT5 itself is not installed here: MetaQuotes' installer (and LiveUpdate) stop with "a debugger
# has been found" under Wine in containers, on Railway and on GitHub's runners alike. The terminal
# runs fine there, so its program files come from a clean archive on the bridge's private volume
# (see entrypoint.sh), which also keeps MetaQuotes' binaries out of this public image.
set -eu

PYTHON_VERSION=3.11.9
MT5_PACKAGE=MetaTrader5==5.0.6231
PYDIR="$WINEPREFIX/drive_c/Python311"

step() { echo "== $(date -u +%H:%M:%S) $*"; }

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

wineserver -k || true
rm -f /tmp/python.zip /tmp/get-pip.py
step "done"
