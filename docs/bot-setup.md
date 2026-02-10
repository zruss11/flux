# Discord & Slack Bot Setup Guide

Flux can send messages to Discord and Slack channels, letting your AI copilot reach you on the platforms you already use. This guide walks you through creating bot tokens and connecting them to Flux.

---

## Discord

### 1. Create a Discord Application

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications).
2. Click **New Application**, give it a name (e.g. "Flux"), and click **Create**.

### 2. Create a Bot and Copy the Token

1. In the left sidebar, click **Bot**.
2. Click **Reset Token** (or **Add Bot** if prompted), then **Copy** the token.
3. Keep this token secret — anyone with it can act as your bot.

> Paste this token into **Flux Settings → Discord Bot Token**.

### 3. Invite the Bot to Your Server

1. In the left sidebar, click **OAuth2 → URL Generator**.
2. Under **Scopes**, check `bot`.
3. Under **Bot Permissions**, check `Send Messages` (permission integer `2048`).
4. Copy the generated URL at the bottom and open it in your browser.
5. Select your server from the dropdown and click **Authorize**.

### 4. Get the Channel ID

1. Open **Discord Settings → Advanced → Developer Mode** and toggle it **on**.
2. Right-click the channel you want Flux to post in.
3. Click **Copy Channel ID**.

> Paste this ID into **Flux Settings → Discord Channel ID**.

### 5. Verify

Ask Flux to send a test message (e.g. "send a message to Discord saying hello"). You should see the message appear in the channel. If the bot shows as offline, that's normal — Flux sends messages via the REST API, not a persistent gateway connection.

---

## Slack

### 1. Create a Slack App

1. Go to [Slack API — Your Apps](https://api.slack.com/apps).
2. Click **Create New App → From scratch**.
3. Name it (e.g. "Flux") and select your workspace.

### 2. Add Bot Permissions

1. In the left sidebar, click **OAuth & Permissions**.
2. Scroll down to **Scopes → Bot Token Scopes**.
3. Click **Add an OAuth Scope** and add `chat:write`.

### 3. Install the App and Copy the Token

1. Scroll back up on the same page and click **Install to Workspace**.
2. Click **Allow** to authorize.
3. Copy the **Bot User OAuth Token** — it starts with `xoxb-`.

> Paste this token into **Flux Settings → Slack Bot Token**.

### 4. Add the Bot to a Channel

1. Open Slack and go to the channel you want Flux to post in.
2. Type `/invite @YourBotName` (use the name you gave the app).
3. The bot must be in the channel to post messages.

### 5. Get the Channel ID

**Option A — From Slack UI:**
1. Right-click the channel name → **View channel details**.
2. Scroll to the bottom — the Channel ID is shown there (starts with `C` or `G`).

**Option B — From the URL:**
1. Open the channel in the Slack web app.
2. The URL looks like `https://app.slack.com/client/TXXXXX/CXXXXX` — the `CXXXXX` part is the Channel ID.

> Paste this ID into **Flux Settings → Slack Channel ID**.

### 6. Verify

Ask Flux to send a test message (e.g. "post to Slack saying hello"). The message should appear in the channel.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| **"Invalid token"** | Re-copy the token — make sure there are no extra spaces. Discord tokens are opaque strings; Slack tokens start with `xoxb-`. |
| **Message not appearing** | Make sure the bot has been invited/added to the target channel. |
| **"Missing permissions"** (Discord) | Re-invite the bot using the OAuth2 URL with `Send Messages` checked. |
| **"not_in_channel"** (Slack) | Run `/invite @YourBotName` in the channel. |
| **"channel_not_found"** (Slack) | Double-check the Channel ID. Use the `C` or `G` prefixed ID, not the channel name. |
| **Bot shows offline** (Discord) | Expected — Flux uses the REST API to send messages, not a persistent WebSocket gateway. The bot will appear offline but can still post. |

---

## Where Tokens Are Stored

Tokens are saved locally in macOS UserDefaults (via Flux Settings). They are **never** sent anywhere except the respective Discord/Slack API endpoints when sending a message. The Node.js sidecar does not store tokens — they are passed from the Swift app at runtime.

---

## Links

- [Discord Developer Portal](https://discord.com/developers/applications)
- [Discord Bot Permissions Calculator](https://discordapi.com/permissions.html)
- [Slack API — Your Apps](https://api.slack.com/apps)
- [Slack OAuth Scopes Reference](https://api.slack.com/scopes)
