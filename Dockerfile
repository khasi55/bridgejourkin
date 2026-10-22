# One MT5 terminal plus the HTTP bridge, under Wine, with Python, the MetaTrader5 package and MT5
# installed at build time from official sources (install-mt5.sh). Build on an x86 host (the GitHub
# Actions workflow); the running container needs no volume and installs nothing.
FROM --platform=linux/amd64 debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    WINEPREFIX=/opt/mt5 \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    DISPLAY=:99 \
    # Skip Wine's Mono and Gecko add-ons: neither MT5 nor the bridge needs them, and their
    # "install?" dialog would wait forever for a click on a headless display.
    WINEDLLOVERRIDES="mscoree,mshtml=" \
    MT5_PATH="C:\\Program Files\\MetaTrader 5\\terminal64.exe"

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg unzip xvfb xdotool \
    && mkdir -pm755 /etc/apt/keyrings \
    && curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
        | gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key \
    && curl -fsSL -o /etc/apt/sources.list.d/winehq-bookworm.sources \
        https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources \
    && apt-get update \
    && apt-get install -y --install-recommends winehq-stable \
    && rm -rf /var/lib/apt/lists/* \
    # Everything here is 64-bit (embeddable Python, MT5), so drop Wine's 32-bit Linux side: with
    # it gone Wine never starts an i386 process, which Rosetta cannot run and QEMU crashes on
    # under Apple Silicon's 16K pages. Harmless on a real x86 host.
    && rm -rf /opt/wine-stable/lib/wine/i386-unix

COPY install-mt5.sh /opt/bridge/
RUN sh /opt/bridge/install-mt5.sh

COPY bridge.py entrypoint.sh /opt/bridge/
RUN chmod +x /opt/bridge/entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["/opt/bridge/entrypoint.sh"]
