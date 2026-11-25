# proxmox-usage

Shared Claude Code and Codex skill for inspecting and operating Proxmox VE
clusters through the REST API with a scoped API token. Reads run freely;
state changes require explicit confirmation and `--yes`.

## Install

```bash
./deploy.sh
```

Creates collision-safe relative symlinks in `~/.claude/skills` and
`~/.agents/skills`. Re-running is safe.

Requirements: Bash, `curl`, `jq`, Python 3 (installer only).

## Setup

1. On a PVE node, create a dedicated user and token scoped to what the agent may
   touch (a pool is safer than `/`):

   ```bash
   pveum user add claude@pve --comment "Claude Code"
   pveum aclmod /pool/<pool> -user claude@pve -role PVEVMAdmin   # or PVEAuditor for read-only
   pveum user token add claude@pve cc --privsep 0                # secret is shown once
   ```

2. On the agent host, create the private config (one file per cluster):

   ```bash
   mkdir -p ~/pve_config && chmod 700 ~/pve_config
   cp pve_config/pve_default.json ~/pve_config/pve_default.json
   chmod 600 ~/pve_config/pve_default.json
   $EDITOR ~/pve_config/pve_default.json
   sshm -s remote:/etc/pve/pve-root-ca.pem ~/pve_config/pve_default-ca.pem <pve-node>
   ```

   Fields: `url`, `token_id`, `token_secret`, optional `ca_file`, optional
   `note`. `PVE_CONFIG_DIR` overrides the directory and `PVE_CLUSTER` the
   default cluster name. `pve.sh` refuses a config readable by group or others.

3. Check: `bash skills/proxmox-usage/tools/pve.sh get /version`

## Layout

- `skills/proxmox-usage/SKILL.md`: operation policy, async tasks, common paths.
- `skills/proxmox-usage/tools/pve.sh`: API helper (`list`, `get`, `--yes post|put|delete`).
- `skills/proxmox-usage/tools/test_pve.sh`: offline self-check with a fake `curl`.
- `skills/proxmox-usage/agents/openai.yaml`: Codex UI metadata only.
- `pve_config/pve_default.json`: example config; real configs live outside the repo.

## Tests

```bash
bash skills/proxmox-usage/tools/test_pve.sh
python3 test_skill_install.py
```
