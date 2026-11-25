#!/usr/bin/env bash
# Deploy the shared proxmox-usage skill with portable relative symlinks.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
rc=0

link_one() {
  local target="$1" name="$2" relative raw
  [[ -e "$target" ]] || { echo "ERROR: missing source: $target" >&2; return 1; }
  mkdir -p "$(dirname "$name")" || return 1
  relative="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$target" "$(dirname "$name")")" || return 1
  if [[ -e "$name" || -L "$name" ]]; then
    if [[ "$(readlink -f "$name" 2>/dev/null || true)" == "$(readlink -f "$target")" ]]; then
      raw="$(readlink "$name" 2>/dev/null || true)"
      [[ "$raw" != /* ]] || { echo "ERROR: absolute symlink at $name" >&2; return 1; }
      echo "ok $name -> $raw"
      return
    fi
    echo "ERROR: $name exists and is not the proxmox-usage link" >&2
    return 1
  fi
  ln -s "$relative" "$name" || return 1
  echo "linked $name -> $relative"
}

for agent_home in "$HOME/.claude" "$HOME/.codex"; do
  skill_home="$agent_home"
  if [[ "$agent_home" == "$HOME/.codex" ]]; then skill_home="$HOME/.agents"; fi
  if [[ -d "$agent_home" ]]; then
    link_one "$REPO/skills/proxmox-usage" "$skill_home/skills/proxmox-usage" || rc=1
  else
    echo "WARNING: $agent_home is not installed; skipping" >&2
  fi
done
exit "$rc"
