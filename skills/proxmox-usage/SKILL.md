---
name: proxmox-usage
description: >-
  Inspect and operate Proxmox VE clusters through the REST API with a scoped
  API token: list nodes, VMs, containers, storage and tasks, read VM status and
  config, and, after explicit user confirmation, start, stop, reboot,
  snapshot, clone or change guests. Use when the user asks about Proxmox, PVE,
  pve, qm/pct guests, or VM/LXC state on a configured cluster.
---

# Proxmox Usage

## Description

All access goes through one helper, `tools/pve.sh`, which reads a private
per-cluster config and calls `https://<host>:8006/api2/json/...` with an API
token. Never SSH to a PVE node or run `qm`/`pct`/`pvesh` as root unless the
user explicitly asks for it in the current turn.

```bash
P=~/github/proxmox-usage/skills/proxmox-usage/tools/pve.sh
bash $P list                                   # configured clusters
bash $P get /cluster/resources type=vm         # every VM and CT, all nodes
bash $P -c lab get /nodes/pve1/qemu/100/status/current
```

## Configuration

- One file per cluster: `~/pve_config/pve_<name>.json` (override the directory
  with `PVE_CONFIG_DIR`, the default cluster with `PVE_CLUSTER`).
- Fields: `url`, `token_id` (`user@realm!tokenname`), `token_secret`, optional
  `ca_file` (PVE `pve-root-ca.pem`; leading `~` allowed), optional `note`.
- The helper refuses a config readable by group or others.
- Never print, echo, log, or commit `token_secret`. Never edit a user's config
  file; tell the user what to change. If no config exists, point the user to
  the repo README setup steps and stop.

## Operation Policy

| Class | Examples | Rule |
|-------|----------|------|
| Read | `get` anything | Run freely. |
| State change | start, shutdown, stop, reboot, suspend, snapshot create, clone, migrate, config edit | State the exact call and target (cluster, node, vmid, name), get the user's OK in this turn, then run with `--yes`. |
| Destructive | delete VM/CT, rollback, delete snapshot, disk/storage/network/firewall/user/ACL changes | Same as above, and also show the current state (status, config or snapshot list) first. One confirmation covers one call; ask again for each further destructive call. |

Before any mutating call, resolve `vmid` to its name and node with
`get /cluster/resources type=vm` so the confirmation names the right guest.
Prefer `shutdown` (graceful) over `stop` unless the user asks for `stop`.

A 403 means the token lacks a privilege. Report the missing privilege path;
do not look for another credential.

## Async Tasks

Mutating calls return a UPID string. Poll until `status` is `stopped`, then
report `exitstatus` (`OK` or the error):

```bash
bash $P get /nodes/<node>/tasks/<UPID>/status
bash $P get /nodes/<node>/tasks/<UPID>/log limit=50   # on failure
```

## Common Paths

- Cluster: `/cluster/status`, `/cluster/resources` (`type=vm|storage|node`),
  `/cluster/tasks`
- Node: `/nodes`, `/nodes/<node>/status`, `/nodes/<node>/storage`
- QEMU: `/nodes/<node>/qemu`, `.../qemu/<vmid>/status/current`,
  `.../qemu/<vmid>/config`, `.../qemu/<vmid>/snapshot`,
  POST `.../qemu/<vmid>/status/{start,shutdown,stop,reboot}`,
  POST `.../qemu/<vmid>/clone newid=<id> name=<name>`
- LXC: the same under `/nodes/<node>/lxc/<vmid>/...`
- Guest agent: `.../qemu/<vmid>/agent/network-get-interfaces` (needs
  qemu-guest-agent in the guest)

Full API reference: https://pve.proxmox.com/pve-docs/api-viewer/
