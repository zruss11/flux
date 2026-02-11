# Discord, Slack & Telegram Bot Setup Guide

Flux can send messages to Discord, Slack, and Telegram, letting your AI copilot reach you on the platforms you already use. This guide walks you through creating bot tokens and connecting them to Flux.

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
4. (Optional) To post to **public** channels without inviting the bot, also add `chat:write.public`.

### 3. Install the App and Copy the Token

1. Scroll back up on the same page and click **Install to Workspace**.
2. Click **Allow** to authorize.
3. Copy the **Bot User OAuth Token** — it starts with `xoxb-`.

> Paste this token into **Flux Settings → Slack Bot Token**.

### 4. Add the Bot to a Channel (Private Channels)

1. Open Slack and go to the channel you want Flux to post in.
2. Type `/invite @YourBotName` (use the name you gave the app).
3. The bot must be in the channel to post messages in **private** channels.

> For **public** channels, you can either invite the bot or grant `chat:write.public` and post without inviting.

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

## Telegram

### 1. Create a Telegram Bot (BotFather)

1. Open Telegram and chat with **@BotFather**.
2. Run `/newbot`, then follow the prompts (name + username ending in `bot`).
3. Copy the bot token.

> Paste this token into **Flux Settings → Telegram Bot Token**.

### 2. Pair Your Account (DM)

1. Open a DM with your bot and send any message.
2. The bot will reply with a **pairing code**.
3. Paste the code into **Flux Settings → Telegram Pairing Code** and approve.

> Pairing is required for private DMs so only approved users can chat with Flux.

### 3. Get Your Chat ID

**Option A — From Bot API (recommended):**
1. Send a DM to your bot (any text).
2. Open `https://api.telegram.org/bot<TOKEN>/getUpdates` in your browser.
3. Find the latest update and copy `message.chat.id`.

**Option B — @userinfobot:**
1. Open Telegram and chat with **@userinfobot**.
2. Copy your numeric ID from the response.

> Paste the ID into **Flux Settings → Telegram Chat ID** (used for outbound messages).

### 4. Groups (Mention Only)

1. Add the bot to a group.
2. Mention it (e.g. `@YourBotName`) to trigger a response.

> Flux only responds to **mentions** in groups by default.

### 5. Verify

Ask Flux to send a test message (e.g. "send a message to Telegram saying hello"). The message should appear in the chat.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| **"Invalid token"** | Re-copy the token — make sure there are no extra spaces. Discord tokens are opaque strings; Slack tokens start with `xoxb-`. |
| **Message not appearing** | Make sure the bot has been invited/added to the target channel. |
| **"Missing permissions"** (Discord) | Re-invite the bot using the OAuth2 URL with `Send Messages` checked. |
| **"not_in_channel"** (Slack) | Run `/invite @YourBotName` in the channel (required for private channels). For public channels, add `chat:write.public` if you want to post without inviting. |
| **"channel_not_found"** (Slack) | Double-check the Channel ID. Use the `C` or `G` prefixed ID, not the channel name. |
| **Bot shows offline** (Discord) | Expected — Flux uses the REST API to send messages, not a persistent WebSocket gateway. The bot will appear offline but can still post. |
| **Telegram DMs ignored** | Pairing is required. DM the bot to get a pairing code, then approve it in Flux Settings. |
| **Telegram groups ignored** | You must **@mention** the bot in group chats. |

---

## Where Tokens Are Stored

Bot tokens are saved locally in macOS Keychain (via Flux Settings). Channel/chat IDs are saved in macOS UserDefaults. Tokens are **never** sent anywhere except the respective Discord/Slack/Telegram API endpoints when sending a message. The Node.js sidecar does not store tokens — they are passed from the Swift app at runtime.

---

## Links

- [Discord Developer Portal](https://discord.com/developers/applications)
- [Discord Bot Permissions Calculator](https://discordapi.com/permissions.html)
- [Slack API — Your Apps](https://api.slack.com/apps)
- [Slack OAuth Scopes Reference](https://api.slack.com/scopes)
- [Telegram Bot API](https://core.telegram.org/bots/api)
