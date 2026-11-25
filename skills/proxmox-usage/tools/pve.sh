#!/usr/bin/env bash
# Thin Proxmox VE REST API client driven by a private per-cluster config.
set -euo pipefail

CONFIG_DIR="${PVE_CONFIG_DIR:-$HOME/pve_config}"

usage() {
  cat <<'EOF'
Usage:
  pve.sh list                                  List configured clusters
  pve.sh [-c NAME] get PATH [key=value ...]    GET /api2/json/PATH
  pve.sh [-c NAME] --yes post|put|delete PATH [key=value ...]
                                               Mutating call; --yes is required

  -c NAME   Use $PVE_CONFIG_DIR/pve_NAME.json (default: PVE_CLUSTER or "default")
  --yes     Confirm a mutating call
  --raw     Print the full response body instead of .data

Config dir: ${PVE_CONFIG_DIR:-~/pve_config}
EOF
}

die() { echo "Error: $*" >&2; exit 1; }

cluster="${PVE_CLUSTER:-default}" yes=0 raw=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c) [[ $# -ge 2 ]] || die "-c needs a name"; cluster="$2"; shift 2 ;;
    --yes) yes=1; shift ;;
    --raw) raw=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) break ;;
  esac
done
[[ $# -ge 1 ]] || { usage >&2; exit 2; }
cmd="$1"; shift

if [[ "$cmd" == list ]]; then
  shopt -s nullglob
  for f in "$CONFIG_DIR"/pve_*.json; do
    name="${f##*/pve_}"; name="${name%.json}"
    jq -r --arg n "$name" '"\($n)\t\(.url)\t\(.token_id)\t\(.note // "")"' "$f"
  done
  exit 0
fi

case "$cmd" in
  get) method=GET ;;
  post|put|delete)
    method="${cmd^^}"
    [[ $yes == 1 ]] || die "$cmd changes cluster state; re-run with --yes after confirming" ;;
  *) usage >&2; exit 2 ;;
esac
[[ $# -ge 1 ]] || die "missing API path"
path="/${1#/}"; shift

config="$CONFIG_DIR/pve_$cluster.json"
[[ -f "$config" ]] || die "no config $config (copy pve_config/pve_default.json from the repo)"
mode="$(stat -c %a "$config")"
(( (8#$mode & 8#077) == 0 )) || die "$config is mode $mode; run chmod 600 $config"

url="$(jq -er .url "$config")" || die "$config: missing url"
token_id="$(jq -er .token_id "$config")" || die "$config: missing token_id"
token_secret="$(jq -er .token_secret "$config")" || die "$config: missing token_secret"
ca_file="$(jq -r '.ca_file // empty' "$config")"
ca_file="${ca_file/#\~/$HOME}"

tls=()
if [[ -n "$ca_file" ]]; then
  [[ -f "$ca_file" ]] || die "ca_file not found: $ca_file"
  tls=(--cacert "$ca_file")
fi

params=()
for kv in "$@"; do
  [[ "$kv" == *=* ]] || die "parameter must be key=value: $kv"
  params+=(--data-urlencode "$kv")
done
# GET and DELETE carry parameters in the query string.
[[ $method == GET || $method == DELETE ]] && params=(-G "${params[@]}")

body="$(mktemp)"
trap 'rm -f "$body"' EXIT
# Header comes from a file descriptor so the secret never appears in argv.
status="$(curl -sS "${tls[@]}" -X "$method" -o "$body" -w '%{http_code}' \
  -H @<(printf 'Authorization: PVEAPIToken=%s=%s\n' "$token_id" "$token_secret") \
  "${params[@]}" "${url%/}/api2/json$path")"

if [[ "$status" != 2* ]]; then
  echo "HTTP $status $method $path" >&2
  cat "$body" >&2; echo >&2
  exit 1
fi
if [[ $raw == 1 ]]; then cat "$body"; else jq '.data' "$body"; fi
