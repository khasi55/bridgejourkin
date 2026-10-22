# One MT5 terminal plus the HTTP bridge, under Wine. This builds the base: the CI workflow then runs
# install-python.sh in a plain container and commits it as the final image. MT5's program files are
# not in the image; entrypoint.sh unpacks them from a clean archive on the bridge's volume.
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

# Wine 9 rather than the current 11: under stock Wine 11 in a container, MT5's protected parts
# refuse to cooperate (the installer and LiveUpdate report a debugger, and the terminal never
# answers the MetaTrader5 package's IPC). Community MT5 images that work run older Wine.
ARG WINE_VERSION=9.0.0.0~bookworm-1

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg unzip xvfb xdotool \
    && mkdir -pm755 /etc/apt/keyrings \
    && curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
        | gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key \
    && curl -fsSL -o /etc/apt/sources.list.d/winehq-bookworm.sources \
        https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources \
    && apt-get update \
    && apt-get install -y --install-recommends \
        "winehq-stable=$WINE_VERSION" "wine-stable=$WINE_VERSION" \
        "wine-stable-amd64=$WINE_VERSION" "wine-stable-i386=$WINE_VERSION" \
    && rm -rf /var/lib/apt/lists/*

COPY install-python.sh bridge.py entrypoint.sh /opt/bridge/
RUN chmod +x /opt/bridge/entrypoint.sh /opt/bridge/install-python.sh

EXPOSE 8000
ENTRYPOINT ["/opt/bridge/entrypoint.sh"]
