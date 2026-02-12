# OpenClaw Messaging Setup Guide

Flux now routes chat-channel delivery through OpenClaw instead of direct Discord/Slack/Telegram bot tokens.

## What Changed

- Flux channel tools are now OpenClaw-based (`send_openclaw_message`).
- Flux no longer needs per-channel bot tokens in app settings for normal messaging.
- Legacy Telegram sidecar polling is disabled by default.

## Prerequisites

1. Install OpenClaw CLI (`openclaw`).
2. Configure OpenClaw with at least one channel/account.

Recommended first-run commands:

```bash
openclaw --profile flux setup
openclaw --profile flux channels login
openclaw --profile flux channels list --json
openclaw --profile flux status --json
```

`--profile flux` keeps OpenClaw state isolated under `~/.openclaw-flux`.

## How Flux Uses OpenClaw

Flux sidecar runs OpenClaw CLI commands directly (no shell interpolation) and supports:

- `openclaw_channels_list`
- `openclaw_status`
- `send_openclaw_message`

Example prompt to Flux:

- "Use OpenClaw to send 'hello' to Slack channel C12345"
- "Check OpenClaw status"
- "List configured OpenClaw channels"

## Security Notes

- Flux does not expose OpenClaw gateway tokens to Swift/UI for these tools.
- Commands are executed with arg arrays (no shell command concatenation).
- Legacy Telegram credential sync is disabled unless `FLUX_ENABLE_LEGACY_TELEGRAM=1`.
- OpenClaw profile isolation limits cross-project credential bleed.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `OpenClaw CLI is unavailable` | Install OpenClaw and ensure `openclaw` is on `PATH`, or set `OPENCLAW_BIN`. |
| `Unknown channel` | Run `openclaw --profile flux channels list --json` and use a configured channel/account. |
| Message send fails auth | Re-run `openclaw --profile flux channels login` for that provider. |
| Sidecar status tool fails | Run `openclaw --profile flux status --json` manually and fix OpenClaw config first. |

## Optional Environment Overrides

- `OPENCLAW_BIN`: absolute path to OpenClaw CLI binary.
- `OPENCLAW_PROFILE`: profile name (defaults to `flux`).
- `OPENCLAW_GATEWAY_PORT`: preferred port for sidecar-managed OpenClaw gateway (defaults to `19089`; sidecar picks another free port if needed).
- `OPENCLAW_TIMEOUT_MS`: command timeout in ms.
- `FLUX_OPENCLAW_AUTOSTART=0`: disable automatic OpenClaw runtime startup from the sidecar.
- `FLUX_ENABLE_LEGACY_TELEGRAM=1`: re-enable old Telegram polling path.
