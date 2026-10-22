"""HTTP bridge to one MT5 terminal through the MetaTrader5 package (Windows Python under Wine).

Guardian's ``SelfHostedConnector`` (guardian/connector/selfhosted.py) is the only client. The bridge
stays dumb on purpose: it calls one whitelisted MetaTrader5 function and returns the raw result, so
every MT5-to-Guardian mapping lives on the Guardian side, typed and unit-tested. Floats leave as
their shortest round-trip string so Guardian builds Decimals without float coercion.

One process serves one MT5 login at a time (the package holds a single terminal connection per
process). The terminal starts with no account; Guardian's ``login`` call, carrying the password
the trader entered in the dashboard, picks one. The password is kept in memory only, to log back
in when the terminal restarts, and is never logged or returned.
"""

import hmac
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

import MetaTrader5 as mt5

TOKEN = os.environ["BRIDGE_TOKEN"]
CALLS = {
    "account_info",
    "terminal_info",
    "positions_get",
    "orders_get",
    "history_deals_get",
    "symbol_info",
    "symbol_info_tick",
    "symbol_select",
    "order_send",
}
FLOAT_KEYS = {"volume", "price", "sl", "tp", "stoplimit"}


def plain(value):
    if hasattr(value, "_asdict"):
        return {k: plain(v) for k, v in value._asdict().items()}
    if isinstance(value, (tuple, list)):
        return [plain(v) for v in value]
    if isinstance(value, dict):
        return {k: plain(v) for k, v in value.items()}
    if isinstance(value, float):
        return repr(value)
    return value


current = {}  # login, password, server of the account Guardian last logged in


def start(login, password, server):
    """Start (or attach to) the terminal already logged in to an account. Started without one,
    MT5 opens its first-run account wizard and waits for a click that a headless host never gets,
    so the terminal starts only at Guardian's first login, with that account."""
    return mt5.initialize(
        path=os.environ["MT5_PATH"], login=login, password=password, server=server, timeout=60_000
    )


def ensure_terminal():
    """(Re)attach to the terminal; it can die under Wine and the package does not reconnect."""
    if mt5.terminal_info() is not None:
        return True
    return bool(current) and start(**current)


class Busy(Exception):
    """The bridge already serves another account. Guardian's api and core processes each track
    their own links, so only the bridge can see that a second account would steal the terminal."""


def login(account, password, server):
    if current and current["login"] != account:
        raise Busy(current["login"])
    wanted = {"login": account, "password": password, "server": server}
    info = mt5.account_info()
    before = None if info is None else info.login
    if mt5.terminal_info() is None:
        ok = start(account, password, server)  # first login: the terminal starts on it
    elif current == wanted and before == account:
        ok = True  # the api and core processes both connect the same account
    else:
        # Log in even on the same account: the password may have changed from the read-only
        # investor one to the trading one, and only a fresh login applies it.
        ok = mt5.login(account, password=password, server=server, timeout=60_000)
        if not ok and before != account:
            # A switch can finish while the package reports an IPC timeout (-10005); only a
            # terminal that actually moved to the account counts, never a failed re-login.
            info = mt5.account_info()
            ok = info is not None and info.login == account and info.server == server
    if ok:
        current.clear()
        current.update(login=account, password=password, server=server)
    return ok


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        """Liveness for the host's health check: no token, nothing about the account but whether
        one is logged in."""
        if self.path != "/health":
            return self._send(404, {"error": "not found"})
        self._send(200, {"ok": True, "account_logged_in": bool(current)})

    def do_POST(self):
        auth = self.headers.get("Authorization", "")
        if not hmac.compare_digest(auth.encode(), f"Bearer {TOKEN}".encode()):
            return self._send(401, {"error": "unauthorized"})
        length = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(length) or b"{}")
        fn = body.get("fn")
        if fn not in CALLS and fn != "login":
            return self._send(404, {"error": f"unknown call {fn!r}"})
        if fn != "login" and not ensure_terminal():
            reason = "terminal unavailable" if current else "no MT5 account logged in yet"
            return self._send(503, {"error": reason, "last_error": mt5.last_error()})
        args = body.get("args", [])
        if fn == "order_send":
            args = [{k: float(v) if k in FLOAT_KEYS else v for k, v in args[0].items()}]
        call = login if fn == "login" else getattr(mt5, fn)
        try:
            result = call(*args, **body.get("kwargs", {}))
        except Busy as busy:
            return self._send(
                409,
                {"error": f"this bridge serves login {busy}; run another bridge for this account"},
            )
        self._send(200, {"result": plain(result), "last_error": list(mt5.last_error())})

    def _send(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format, *args):
        pass  # request lines carry nothing useful and the default goes to stderr per call


def main():
    print(
        "mt5 bridge ready; waiting for Guardian to log in an account", file=sys.stderr, flush=True
    )
    # ponytail: single-threaded server serialises every call, which the MetaTrader5 package needs
    # anyway; one bridge per account is the scaling unit.
    # 0.0.0.0 inside a container; run-mac.sh binds 127.0.0.1 so the Mac does not expose it on LAN.
    address = (os.environ.get("BRIDGE_HOST", "0.0.0.0"), int(os.environ.get("BRIDGE_PORT", "8000")))
    HTTPServer(address, Handler).serve_forever()


if __name__ == "__main__":
    main()
