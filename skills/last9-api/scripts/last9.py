#!/usr/bin/env python3
"""Last9 REST API helper: login once, then `api` calls with auto-refreshed tokens.

Stdlib only. Never prints tokens (except `token`, which is meant for $(...)).
"""
import argparse
import base64
import getpass
import hashlib
import json
import os
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from datetime import datetime, timezone

API_ACCESS_URL = "https://app.last9.io/settings/api-access"
REFRESH_MARGIN = 3600  # re-exchange when the cached access token has <= 1h left
TIMEOUT = 60


def die(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(1)


def config_dir():
    return os.environ.get("LAST9_CONFIG_DIR") or os.path.expanduser("~/.last9")


def write_private(path, obj):
    """Atomic write, file 0600, parent dir 0700."""
    d = os.path.dirname(path)
    os.makedirs(d, mode=0o700, exist_ok=True)
    os.chmod(d, 0o700)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp-")  # created 0600
    with os.fdopen(fd, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, path)


def read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def creds_path():
    return os.path.join(config_dir(), "credentials")


def load_creds():
    return read_json(creds_path(), {"profiles": {}})


def decode_claims(token):
    try:
        seg = token.split(".")[1]
        return json.loads(base64.urlsafe_b64decode(seg + "=" * (-len(seg) % 4)))
    except Exception:
        die("refresh token is not a valid JWT")


def host_org(claims):
    aud = claims.get("aud")
    aud = aud[0] if isinstance(aud, list) and aud else aud
    org = claims.get("organization_slug")
    if not aud or not org:
        die("refresh token is missing the 'aud' or 'organization_slug' claim")
    host = aud.split("://", 1)[-1].split("/", 1)[0]
    return host, org


class Ctx:
    """Resolved identity for one profile (or the env token)."""

    def __init__(self, profile, refresh=None):
        env = os.environ.get("LAST9_REFRESH_TOKEN", "").strip()
        if refresh:  # explicit token from `login`
            self.refresh, self.source, self.cache_key = refresh, "file", profile
        elif env:
            self.refresh, self.source = env, "env"
            self.cache_key = "env-" + hashlib.sha256(env.encode()).hexdigest()[:12]
        else:
            self.refresh = load_creds().get("profiles", {}).get(profile, {}).get("refresh_token")
            self.source, self.cache_key = "file", profile
            if not self.refresh:
                die("not logged in — run: python3 %s login" % os.path.abspath(__file__))
        self.profile = profile
        saved = load_creds().get("profiles", {}).get(profile, {}).get("region")
        self.region = os.environ.get("LAST9_REGION", "").strip() or saved
        self.claims = decode_claims(self.refresh)
        self.host, self.org = host_org(self.claims)

    @property
    def cache_file(self):
        return os.path.join(config_dir(), "cache", self.cache_key + ".json")


def exchange(host, refresh):
    req = urllib.request.Request(
        "https://%s/api/v4/oauth/access_token" % host,
        data=json.dumps({"refresh_token": refresh}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code in (400, 401, 403):
            die("refresh token invalid, expired, or revoked — generate a new one at " + API_ACCESS_URL)
        die("token exchange failed: HTTP %d" % e.code)
    except urllib.error.URLError as e:
        die("token exchange failed: %s" % e.reason)


def save_cache(ctx, resp):
    entry = {"access_token": resp["access_token"], "expires_at": resp["expires_at"]}
    write_private(ctx.cache_file, entry)
    return entry


def access_token(ctx, force=False):
    if not force:
        c = read_json(ctx.cache_file, {})
        if c.get("access_token") and c.get("expires_at", 0) - time.time() > REFRESH_MARGIN:
            return c["access_token"]
    return save_cache(ctx, exchange(ctx.host, ctx.refresh))["access_token"]


def iso(ts):
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def info_lines(ctx):
    c = ctx.claims
    return [
        "profile: %s" % ctx.profile,
        "region: %s" % (ctx.region or "not set"),
        "org: %s" % ctx.org,
        "host: %s" % ctx.host,
        "scopes: %s" % ", ".join(c.get("scopes") or []),
        "refresh token expires: %s" % (iso(c["exp"]) if "exp" in c else "unknown"),
    ]


# ---- subcommands ----

def cmd_login(a):
    if a.with_token:
        token = sys.stdin.read().strip()
    else:
        print("Create a refresh token at %s (Admins create refresh tokens; "
              "Editors must ask an Admin)." % API_ACCESS_URL)
        if not a.no_browser:
            webbrowser.open(API_ACCESS_URL)
        token = getpass.getpass("Paste refresh token (input hidden): ").strip()
    if not token:
        die("no token provided")
    claims = decode_claims(token)
    host, _ = host_org(claims)
    resp = exchange(host, token)  # validate before saving anything
    creds = load_creds()
    old = creds.get("profiles", {}).get(a.profile, {})
    entry = {"refresh_token": token}
    if a.region or old.get("region"):  # keep the saved region unless a new one is given
        entry["region"] = a.region or old["region"]
    creds.setdefault("profiles", {})[a.profile] = entry
    write_private(creds_path(), creds)
    ctx = Ctx(a.profile, refresh=token)
    save_cache(ctx, resp)
    print("\n".join(["logged in"] + info_lines(ctx)))


def cmd_token(a):
    print(access_token(Ctx(a.profile)))


def cmd_status(a):
    ctx = Ctx(a.profile)
    cached = read_json(ctx.cache_file, {})
    exp = cached.get("expires_at")
    lines = info_lines(ctx)
    lines.insert(1, "source: %s" % ctx.source)
    lines.append("email: %s" % ctx.claims.get("email", "unknown"))
    lines.append("access token expires: %s" % (iso(exp) if exp else "none"))
    print("\n".join(lines))


def cmd_logout(a):
    creds = load_creds()
    removed = creds.get("profiles", {}).pop(a.profile, None)
    if removed:
        write_private(creds_path(), creds)
        try:
            os.remove(os.path.join(config_dir(), "cache", a.profile + ".json"))
        except OSError:
            pass
    print("logged out profile %r" % a.profile if removed else "profile %r not found" % a.profile)
    if os.environ.get("LAST9_REFRESH_TOKEN"):
        print("note: LAST9_REFRESH_TOKEN is set and still in effect")


def resolve_url(ctx, path, queries):
    if path.startswith(("http://", "https://")):
        if urllib.parse.urlsplit(path).hostname != ctx.host:
            die("refusing to send token to foreign host (expected %s)" % ctx.host)
        url = path
    elif path.startswith("/api/"):
        url = "https://%s%s" % (ctx.host, path)
    else:
        url = "https://%s/api/v4/organizations/%s/%s" % (ctx.host, ctx.org, path.lstrip("/"))
    if queries:
        qs = urllib.parse.urlencode([(k, v) for k, _, v in (q.partition("=") for q in queries)])
        url += ("&" if "?" in url else "?") + qs
    # logs/ and cat/ endpoints 400 without region (live-verified)
    sp = urllib.parse.urlsplit(url)
    rel = sp.path[len("/api/v4/organizations/%s/" % ctx.org):] \
        if sp.path.startswith("/api/v4/organizations/%s/" % ctx.org) else ""
    if rel.startswith(("logs/", "cat/")) and "region" not in urllib.parse.parse_qs(sp.query):
        if not ctx.region:
            die("region required for logs/traces endpoints \u2014 pass -q region=<r>, "
                "set LAST9_REGION, or run: login --region <r>")
        url += ("&" if sp.query else "?") + urllib.parse.urlencode({"region": ctx.region})
    return url


class NoRedirect(urllib.request.HTTPRedirectHandler):
    # Don't follow redirects: urllib would forward the token header to the new host.
    def redirect_request(self, *args, **kwargs):
        return None


def send(method, url, token, data, headers):
    h = {"X-LAST9-API-TOKEN": "Bearer " + token}
    if data is not None:
        h["Content-Type"] = "application/json"
    h.update(headers)
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except urllib.error.URLError as e:
        die("request failed: %s" % e.reason)


def cmd_api(a):
    ctx = Ctx(a.profile)
    url = resolve_url(ctx, a.path, a.q)
    data = None
    if a.d is not None:
        raw = sys.stdin.buffer.read() if a.d == "-" else None
        if a.d.startswith("@"):
            with open(a.d[1:], "rb") as f:
                raw = f.read()
        data = raw if raw is not None else a.d.encode()
    headers = dict(h.split(":", 1) for h in a.H)
    headers = {k.strip(): v.strip() for k, v in headers.items()}
    urllib.request.install_opener(urllib.request.build_opener(NoRedirect))
    method = a.method.upper()
    code, body = send(method, url, access_token(ctx), data, headers)
    if code == 401 or (400 <= code < 500 and b"expired" in body.lower()):
        code, body = send(method, url, access_token(ctx, force=True), data, headers)  # retry once
    sys.stdout.flush()
    sys.stdout.buffer.write(body)
    ok = 200 <= code < 300
    if a.i or not ok:
        sys.stderr.write("HTTP %d\n" % code)
    sys.exit(0 if ok else 1)


def main(argv=None):
    p = argparse.ArgumentParser(description="Last9 REST API helper")
    p.add_argument("--profile", default=os.environ.get("LAST9_PROFILE") or "default")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("login", help="save a refresh token (validated by exchange)")
    s.add_argument("--with-token", action="store_true", help="read token from stdin")
    s.add_argument("--no-browser", action="store_true")
    s.add_argument("--region", help="default region for logs/traces endpoints (e.g. ap-south-1)")
    s.set_defaults(fn=cmd_login)
    sub.add_parser("token", help="print a valid access token").set_defaults(fn=cmd_token)
    sub.add_parser("status", help="show identity, no secrets").set_defaults(fn=cmd_status)
    sub.add_parser("logout", help="forget the profile").set_defaults(fn=cmd_logout)
    s = sub.add_parser("api", help="authenticated request")
    s.add_argument("method")
    s.add_argument("path", help="org-relative path, /api/... path, or full URL on your host")
    s.add_argument("-d", metavar="DATA", help="body: literal, @file, or - for stdin")
    s.add_argument("-q", action="append", default=[], metavar="K=V", help="query param (repeatable)")
    s.add_argument("-H", action="append", default=[], metavar="'K: V'", help="extra header (repeatable)")
    s.add_argument("-i", action="store_true", help="always print HTTP status to stderr")
    s.set_defaults(fn=cmd_api)
    a = p.parse_args(argv)
    if "/" in a.profile or a.profile.startswith("."):
        die("invalid profile name")
    a.fn(a)


if __name__ == "__main__":
    main()
