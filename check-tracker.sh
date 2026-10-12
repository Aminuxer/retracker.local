#!/usr/bin/env bash

# check-tracker.sh - availability check for a BitTorrent tracker (announce + scrape)   [ Aminuxer + QWEN-3.6-27B-AI ]
#
# Usage:
#   ./check-tracker.sh [URL]
#   Default URL: retracker.local announce with a test info_hash
#
# Checks:
#   1. DNS resolution of the tracker host
#   2. announce: HTTP 200 + bencoded body with interval/peers
#   3. scrape:   HTTP 200 + bencoded body with a "file" dict
#      The scrape URL is derived from the announce URL: the path segment
#      "announce" is replaced with "scrape" and the query becomes
#      min_interval + info_hash. A 404/501 answer to scrape means the tracker
#      has no scrape support - warning only, not a failure.
#
# HTTP client: auto-detected in order curl > wget > nc; force one with
#   HTTP_CLIENT=auto|curl|wget|nc
#   curl: full timing breakdown (DNS/connect/TTFB)
#   wget: wall time only
#   nc:   HTTP only (no TLS), raw HTTP/1.0 request via netcat, wall time only
#
# Env vars:
#   TIMEOUT - request timeout in seconds (default 15)
#   MIN_INTERVAL - min_interval value sent to /scrape/ (default 300)
#
# Exit codes:
#   0 - OK (announce 200 + parsed; scrape 200 + parsed or not supported)
#   1 - network error / unexpected HTTP status / unparseable body
#   2 - DNS does not resolve
#   3 - no usable HTTP client (curl/wget/nc) available

set -u

DEFAULT_URL='http://retracker.local/announce/?info_hash=12345678901234567890&port=6969&interval=12000&ip=127.0.69.69'




URL="${1:-$DEFAULT_URL}"
TIMEOUT="${TIMEOUT:-15}"
CLIENT="${HTTP_CLIENT:-auto}"
MIN_INTERVAL="${MIN_INTERVAL:-300}"

case "$CLIENT" in
    auto|curl|wget|nc) ;;
    *)
        echo "FAIL [DEP]: unknown HTTP_CLIENT '$CLIENT' (expected auto|curl|wget|nc)"
        exit 3
        ;;
esac

# A full announce URL must carry a port parameter; if it is missing, the shell
# most likely split an unquoted URL at '&' before it reached this script.
if [[ "$URL" != *port=* ]]; then
    echo "WARN: no 'port=' in URL - if you passed a full announce URL, quote it:"
    echo "      ./check-tracker.sh 'http://host/announce/?info_hash=...&port=6011'"
    echo
fi

echo "=== Checking announce ==="
echo "URL: $URL"
echo

# --- 1. DNS ---
hostpart=$(sed -E 's~^https?://~~; s~/.*$~~; s~:.*$~~' <<<"$URL")
dns_line=$(getent hosts "$hostpart" 2>/dev/null || true)
if [[ -z "$dns_line" ]]; then
    echo "FAIL [DNS]: $hostpart does not resolve (check /etc/hosts or DNS)"
    exit 2
fi
ips=$(awk '{print $1}' <<<"$dns_line" | paste -sd, -)
echo "DNS: $hostpart -> $ips"

# --- 2. HTTP client selection ---
F_BODY=$(mktemp)
F_RAW=$(mktemp)
trap 'rm -f "$F_BODY" "$F_RAW"' EXIT

# select the HTTP client (auto: first available of curl, wget, nc)
if [[ "$CLIENT" == "auto" ]]; then
    if command -v curl >/dev/null 2>&1; then
        CLIENT=curl
    elif command -v wget >/dev/null 2>&1; then
        CLIENT=wget
    elif command -v nc >/dev/null 2>&1; then
        CLIENT=nc
    else
        CLIENT=""
    fi
fi
if [[ -z "$CLIENT" ]]; then
    echo "FAIL [DEP]: no HTTP client available (need curl, wget or nc)"
    exit 3
fi
echo "HTTP client: $CLIENT"
echo

# --- fetch helpers ---
# $F_URL = request URL, body goes to $F_BODY
# set: code, timings, t_total, size, fetch_rc
fetch_curl() {
    local stats rc t_dns t_conn t_ttfb
    stats=$(curl -sS -o "$F_BODY" \
        -w '%{http_code} %{time_namelookup} %{time_connect} %{time_starttransfer} %{time_total} %{size_download}' \
        --max-time "$TIMEOUT" "$F_URL" 2>/dev/null)
    rc=$?
    read -r code t_dns t_conn t_ttfb t_total size <<<"$stats"
    timings="DNS ${t_dns:-?}s | connect ${t_conn:-?}s | TTFB ${t_ttfb:-?}s"
    if (( rc != 0 )); then
        code=""
    fi
    fetch_rc=$rc
}

fetch_wget() {
    local t0 t1 log
    t0=$(date +%s%N)
    log=$(wget -q -S -O "$F_BODY" -T "$TIMEOUT" -t 1 "$F_URL" 2>&1)
    fetch_rc=$?
    t1=$(date +%s%N)
    t_total=$(awk -v a="$t0" -v b="$t1" 'BEGIN {printf "%.3f", (b-a)/1e9}')
    code=$(awk '/^ *HTTP\// {c=$2} END {print c}' <<<"$log")
    if [[ ! -f "$F_BODY" ]]; then
        : > "$F_BODY"
    fi
    size=$(wc -c < "$F_BODY")
    timings="DNS n/a | connect n/a | TTFB n/a"
}

fetch_nc() {
    local rest hostport host port path req t0 t1 nl found line header_bytes
    if [[ "$F_URL" == https://* ]]; then
        echo "FAIL [DEP]: nc cannot handle HTTPS, use curl or wget"
        exit 3
    fi
    rest=${F_URL#*://}
    hostport=${rest%%/*}
    if [[ "$rest" == */* ]]; then path=/${rest#*/}; else path=/; fi
    if [[ "$hostport" == *:* ]]; then
        host=${hostport%%:*}
        port=${hostport##*:}
    else
        host=$hostport
        port=80
    fi
    req=$(printf 'GET %s HTTP/1.0\r\nHost: %s\r\nUser-Agent: check-tracker.sh/1.0\r\nConnection: close\r\n\r\n' "$path" "$host")

    t0=$(date +%s%N)
    printf '%s' "$req" | timeout "$TIMEOUT" nc "$host" "$port" > "$F_RAW" 2>/dev/null
    fetch_rc=$?
    t1=$(date +%s%N)
    t_total=$(awk -v a="$t0" -v b="$t1" 'BEGIN {printf "%.3f", (b-a)/1e9}')
    timings="DNS n/a | connect n/a | TTFB n/a"

    if [[ ! -s "$F_RAW" ]]; then
        code=""
        size=0
        return 0
    fi
    code=$(head -n1 "$F_RAW" | awk '{print $2}')
    # header ends at the first blank line; headers are plain text, so count
    # lines with read, then take the body from a byte offset (binary safe)
    nl=0
    found=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        nl=$(( nl + 1 ))
        if [[ "${line%$'\r'}" == "" ]]; then
            found=1
            break
        fi
    done < "$F_RAW"
    if (( found == 0 )); then
        echo "FAIL [HTTP]: malformed response (no header/body separator)"
        head -c 200 "$F_RAW" | cat -v
        echo
        exit 1
    fi
    header_bytes=$(head -n "$nl" "$F_RAW" | wc -c)
    tail -c "+$(( header_bytes + 1 ))" "$F_RAW" > "$F_BODY"
    size=$(wc -c < "$F_BODY")
    # a complete response was received, so success even if timeout later killed nc
    fetch_rc=0
}

run_fetch() {
    if [[ "$CLIENT" == "curl" ]]; then
        fetch_curl
    elif [[ "$CLIENT" == "wget" ]]; then
        fetch_wget
    else
        fetch_nc
    fi
}

# fetch $1 into $F_BODY and print the timing line
# returns 0 on HTTP 200, 2 on any other status, exits 1 on network failure
http_check() {
    F_URL=$1
    run_fetch
    code=${code//$'\r'/}
    if (( fetch_rc != 0 )) && [[ -z "$code" ]]; then
        echo "FAIL [NET]: $CLIENT exit $fetch_rc (no HTTP response, timeout=${TIMEOUT}s)"
        exit 1
    fi
    echo "HTTP ${code:-?} | ${timings} | total ${t_total}s | ${size} B"
    if [[ "$code" == "200" ]]; then
        return 0
    fi
    return 2
}

rc=0
http_check "$URL" || rc=$?
if (( rc != 0 )); then
    echo "FAIL [HTTP]: unexpected status ${code:-n/a}"
    [[ -s "$F_BODY" ]] && head -c 300 "$F_BODY" && echo
    exit 1
fi

# --- 3. Parse bencoded announce response ---
if (( size == 0 )); then
    echo "FAIL [BODY]: empty response (200 with no body)"
    exit 1
fi

if command -v python3 >/dev/null 2>&1; then
    echo
    python3 - "$F_BODY" <<'PY' || { echo "WARN: could not parse bencoded response, raw data below"; head -c 200 "$F_BODY" | cat -v; echo; exit 1; }
import socket
import struct
import sys

data = open(sys.argv[1], 'rb').read()
i = 0

def rd():
    global i
    c = data[i:i+1]
    if c == b'i':
        j = data.index(b'e', i)
        v = int(data[i+1:j])
        i = j + 1
        return v
    if c == b'l':
        i += 1
        out = []
        while data[i:i+1] != b'e':
            out.append(rd())
        i += 1
        return out
    if c == b'd':
        i += 1
        out = {}
        while data[i:i+1] != b'e':
            k = rd()
            v = rd()
            out[k] = v
        i += 1
        return out
    j = data.index(b':', i)
    n = int(data[i:j])
    i = j + 1 + n
    return data[j+1:i]

def fmt4(b):
    ip = '%d.%d.%d.%d' % (b[0], b[1], b[2], b[3])
    port = struct.unpack('>H', b[4:6])[0]
    return '%s:%d' % (ip, port)

def fmt6(b):
    ip = socket.inet_ntop(socket.AF_INET6, b[:16])
    port = struct.unpack('>H', b[16:18])[0]
    return '[%s]:%d' % (ip, port)

v = rd()
for k in v:
    val = v[k]
    key = k.decode('ascii', 'replace') if isinstance(k, bytes) else k
    if key == 'peers' and isinstance(val, bytes):
        n = len(val) // 6
        print('peers: %d' % n)
        if n:
            sample = ', '.join(fmt4(val[p:p+6]) for p in range(0, min(n, 5) * 6, 6))
            print('  sample: %s' % sample)
    elif key == 'peers' and isinstance(val, list):
        print('peers: %d (list of strings)' % len(val))
    elif key == 'peers6' and isinstance(val, bytes):
        n = len(val) // 18
        print('peers6: %d' % n)
        if n:
            sample = ', '.join(fmt6(val[p:p+18]) for p in range(0, min(n, 3) * 18, 18))
            print('  sample: %s' % sample)
    else:
        if isinstance(val, bytes):
            val = val.decode('ascii', 'replace')
        print('%s: %s' % (key, val))
PY
else
    # Fallback without python3: numeric fields only
    echo
    sed -n 's/.*8:interval\([0-9]*\).*/interval: \1/p' "$F_BODY"
    sed -n 's/.*12:min interval\([0-9]*\).*/min interval: \1/p' "$F_BODY"
    echo "(python3 not found - peers not decoded)"
fi

# --- 4. scrape check ---
# Derive the scrape URL from the announce URL: same scheme+host, path segment
# "announce" replaced with "scrape", query = min_interval + first info_hash.
SCRAPE_URL=""
SCRAPE_IH=""
if [[ "$URL" == *info_hash=* ]]; then
    SCRAPE_IH=${URL#*info_hash=}
    SCRAPE_IH=${SCRAPE_IH%%&*}
    qpath=$(sed -E 's~^https?://[^/]*~~' <<<"$URL")
    apath=${qpath%%\?*}
    if [[ "$apath" == *announce* ]]; then
        apath=${apath/announce/scrape}
    else
        apath=/scrape/
    fi
    base=$(sed -E 's~^(https?://[^/]*).*~\1~' <<<"$URL")
    SCRAPE_URL="${base}${apath}?min_interval=${MIN_INTERVAL}&info_hash=${SCRAPE_IH}"
fi

echo
echo "=== Checking scrape ==="
if [[ -z "$SCRAPE_URL" ]]; then
    echo "WARN: no info_hash in URL - scrape check skipped"
else
    echo "URL: $SCRAPE_URL"
    echo
    rc=0
    http_check "$SCRAPE_URL" || rc=$?
    if (( rc != 0 )); then
        if [[ "$code" == "404" || "$code" == "501" ]]; then
            echo "WARN [SCRAPE]: HTTP $code - tracker does not implement /scrape/ (not fatal)"
        else
            echo "FAIL [HTTP]: unexpected status ${code:-n/a}"
            [[ -s "$F_BODY" ]] && head -c 300 "$F_BODY" && echo
            exit 1
        fi
    else
        if (( size == 0 )); then
            echo "FAIL [BODY]: empty response (200 with no body)"
            exit 1
        fi
        if command -v python3 >/dev/null 2>&1; then
            echo
            python3 - "$F_BODY" "$SCRAPE_IH" <<'PY' || { echo "WARN: could not parse bencoded scrape response, raw data below"; head -c 200 "$F_BODY" | cat -v; echo; exit 1; }
import sys
import urllib.parse

data = open(sys.argv[1], 'rb').read()
i = 0

def rd():
    global i
    c = data[i:i+1]
    if c == b'i':
        j = data.index(b'e', i)
        v = int(data[i+1:j])
        i = j + 1
        return v
    if c == b'l':
        i += 1
        out = []
        while data[i:i+1] != b'e':
            out.append(rd())
        i += 1
        return out
    if c == b'd':
        i += 1
        out = {}
        while data[i:i+1] != b'e':
            k = rd()
            v = rd()
            out[k] = v
        i += 1
        return out
    j = data.index(b':', i)
    n = int(data[i:j])
    i = j + 1 + n
    return data[j+1:i]

try:
    v = rd()
except (ValueError, IndexError):
    print('invalid bencoded body')
    sys.exit(1)

if not isinstance(v, dict) or b'file' not in v:
    print('no "file" key in top-level dict')
    sys.exit(1)

file = v[b'file']
if not isinstance(file, dict):
    print('"file" is not a dict')
    sys.exit(1)

print('file: %d entr%s' % (len(file), 'y' if len(file) == 1 else 'ies'))
if b'min_interval' in v:
    print('min_interval: %s' % v[b'min_interval'])

# unquote_to_bytes (not unquote): returns raw bytes for percent-escaped
# info_hash values; local python3.12 returns str from unquote(bytes)
raw = urllib.parse.unquote_to_bytes(sys.argv[2])
if len(raw) != 20:
    print('info_hash %r is not 20 raw bytes - cannot match it in "file"' % sys.argv[2])
elif raw in file:
    e = file[raw]
    if not isinstance(e, dict):
        print('info_hash %s -> entry is not a dict: %r' % (raw.decode('ascii', 'replace'), e))
        sys.exit(1)
    parts = []
    for key in (b'seeds', b'leeches', b'completed'):
        if key in e:
            parts.append('%s %s' % (key.decode(), e[key]))
    print('info_hash %s -> %s' % (raw.decode('ascii', 'replace'), ', '.join(parts) if parts else 'empty entry'))
else:
    print('info_hash %s: no entry in "file" dict (tracker reports nothing for it)' % raw.decode('ascii', 'replace'))
PY
        else
            # Fallback without python3: only the mandatory body prefix
            echo
            if head -c 7 "$F_BODY" | grep -q '^d4:file'; then
                echo 'body starts with "d4:file" (python3 not found - entries not decoded)'
            else
                echo "FAIL [BODY]: body does not start with 'd4:file'"
                head -c 200 "$F_BODY" | cat -v
                echo
                exit 1
            fi
        fi
    fi
fi

echo
echo "OK"
