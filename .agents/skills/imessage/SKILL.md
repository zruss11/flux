---
name: imessage
description: Use built-in Flux Messages tools (AppleScript automation, no imsg CLI).
---

# Messages.app via Flux tools

Use Flux's dedicated iMessage tools instead of the `imsg` CLI.

## Use these tools

- `imessage_list_accounts`
- `imessage_list_chats`
- `imessage_send_message`

## Guidance

- Prefer the built-in `imessage_*` tools for all Messages workflows.
- Do **not** require `imsg` install or Full Disk Access for this skill.
- AppleScript can list chats/accounts and send messages, but it cannot fetch full historical transcript data.
- Confirm recipient + message content before sending.
- If macOS blocks automation, ask the user to enable: **System Settings → Privacy & Security → Automation → Flux → Messages**.
