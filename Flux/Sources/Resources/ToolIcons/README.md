# Tool Icons

Drop custom tool/logo icon files here to replace SF Symbol fallbacks in the **Called Tools** bubble.

Supported formats: PNG, PDF, SVG converted to PDF/PNG (recommended 20x20 to 64x64, transparent background).

## Naming convention

Use one of these names (without extension):

- `tool-terminal`
- `tool-calendar`
- `tool-linear`
- `tool-notion`
- `tool-github`
- `tool-automation`
- `tool-screen`
- `tool-selection`
- `tool-clipboard`
- `tool-session`
- `tool-delegate`
- `tool-datetime`
- `tool-file`
- `tool-git`
- `tool-generic`

For MCP servers, Flux also checks:

- `tool-<serverId>`
- `<serverId>`

Example: for an MCP server id `slack`, either `tool-slack.png` or `slack.png` will be used.

## Behavior

- If a custom icon exists, it is used.
- Otherwise, Flux falls back to a built-in SF Symbol for that tool kind.
- Icons stack one per unique tool kind in each "Called Tools" bubble.
