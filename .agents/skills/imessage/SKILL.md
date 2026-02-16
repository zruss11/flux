---
name: imessage
description: Read and send iMessage/SMS from macOS using the imsg CLI (steipete/imsg).
---

# iMessage via imsg

Use `imsg` to list chats, read history, and send iMessage/SMS from Messages.app on macOS.

## Requirements

- Messages.app is signed in and synced.
- `imsg` is installed (`brew install steipete/tap/imsg`).
- Terminal/Flux has Full Disk Access for reading chat DB.
- Flux has Automation permission for controlling Messages.app when sending.

## Preflight (always run first)

1. Verify CLI availability:

```bash
command -v imsg
```

2. If `imsg` is missing, do **not** continue with message actions yet. Ask the user for permission to install it and offer:

```bash
brew install steipete/tap/imsg
```

3. After installation, re-check and then continue:

```bash
imsg --help
imsg chats --limit 5 --json
```

## Actions

### List recent chats

```bash
imsg chats --limit 10 --json
```

### Read chat history

```bash
imsg history --chat-id 1 --limit 20 --attachments --json
```

### Watch a chat live

```bash
imsg watch --chat-id 1 --attachments
```

### Send a message

```bash
imsg send --to "+14155551212" --text "hi"
```

### Send with attachment

```bash
imsg send --to "+14155551212" --text "see attached" --file /path/pic.jpg
```

## Notes

- Use `--service imessage|sms|auto` to control delivery method.
- Prefer `--json` when reading data so results are machine-parseable.
- Confirm recipient + message text before sending.
