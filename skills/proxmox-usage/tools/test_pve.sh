#!/usr/bin/env bash
# Offline self-check for pve.sh using a fake curl; no network, no real config.
set -euo pipefail

PVE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pve.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/cfg"

# Fake curl: record argv and the header file contents, emit a canned response.
cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=""
printf '%s\n' "$@" > "$CURL_LOG.argv"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -H) [[ "$2" == @* ]] && cat "${2#@}" > "$CURL_LOG.header"; shift 2 ;;
    *) shift ;;
  esac
done
echo '{"data":[{"node":"pve1"}]}' > "$out"
printf '%s' "${FAKE_STATUS:-200}"
EOF
chmod +x "$tmp/bin/curl"

cfg="$tmp/cfg/pve_default.json"
cat > "$cfg" <<'EOF'
{"url": "https://192.0.2.10:8006/", "token_id": "claude@pve!cc", "token_secret": "s3cret", "note": "test"}
EOF
export PATH="$tmp/bin:$PATH" PVE_CONFIG_DIR="$tmp/cfg" CURL_LOG="$tmp/curl"
fail() { echo "FAIL: $*" >&2; exit 1; }

chmod 644 "$cfg"
bash "$PVE" get /nodes 2>/dev/null && fail "world-readable config accepted"
chmod 600 "$cfg"

[[ "$(bash "$PVE" get /nodes | jq -r '.[0].node')" == pve1 ]] || fail "GET output"
grep -qx 'https://192.0.2.10:8006/api2/json/nodes' "$CURL_LOG.argv" || fail "URL join"
grep -q s3cret "$CURL_LOG.argv" && fail "secret leaked into argv"
grep -qx 'Authorization: PVEAPIToken=claude@pve!cc=s3cret' "$CURL_LOG.header" || fail "auth header"

bash "$PVE" post /nodes/pve1/qemu/100/status/start 2>/dev/null && fail "write without --yes accepted"
bash "$PVE" --yes post /nodes/pve1/qemu/100/status/start >/dev/null || fail "write with --yes"
grep -qx POST "$CURL_LOG.argv" || fail "method"

FAKE_STATUS=401 bash "$PVE" get /nodes 2>/dev/null && fail "HTTP error not propagated"
bash "$PVE" -c missing get /nodes 2>/dev/null && fail "missing cluster accepted"
[[ "$(bash "$PVE" list | cut -f1)" == default ]] || fail "list"

echo "PASS: pve.sh permission gate, auth header off argv, write gate, errors, list"
