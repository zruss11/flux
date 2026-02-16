---
name: kroger
description: Find Kroger locations/products and start an authenticated customer cart via Kroger APIs.
---

# Kroger API Skill

Use this skill to:
- Search Kroger locations
- Search Kroger products
- Start/add items to a customer's Kroger cart

This skill uses a helper CLI script:
- `kroger.mjs` (in the same folder as this `SKILL.md`)

Before running commands, resolve `SKILL_DIR` as the parent directory of this `SKILL.md`, then run:
- `node "$SKILL_DIR/kroger.mjs" ...`

## Authentication model

- **Locations + Products** use **Client Context** (`client_credentials` token).
- **Cart** uses **Customer Context** (OAuth2 Authorization Code flow).

## Required environment variables

- `KROGER_CLIENT_ID`
- `KROGER_CLIENT_SECRET`

Optional:
- `KROGER_REDIRECT_URI` (default: `http://localhost:8765/callback`)
- `KROGER_CLIENT_SCOPE` (default: `product.compact location.compact`)
- `KROGER_CART_PATH` (default: `/v1/cart/add`)

## Command reference

### 1) Create auth URL for customer consent (needed for cart actions)

```bash
node "$SKILL_DIR/kroger.mjs" oauth auth-url --scopes "cart.basic profile.compact product.compact" --open
```

Then exchange returned `code`:

```bash
node "$SKILL_DIR/kroger.mjs" oauth exchange-code --code "<AUTH_CODE>" --redirect-uri "<REDIRECT_URI>"
```

### 2) Find locations

```bash
node "$SKILL_DIR/kroger.mjs" locations search --zip 45140 --radius 20 --limit 5
```

or

```bash
node "$SKILL_DIR/kroger.mjs" locations search --lat 39.259 --lon -84.265 --limit 5
```

### 3) Find products

```bash
node "$SKILL_DIR/kroger.mjs" products search --term "fat free milk" --location-id 01400943 --limit 5
```

### 4) Add one item to cart

```bash
node "$SKILL_DIR/kroger.mjs" cart add --upc 0001111060903 --qty 1 --modality DELIVERY
```

### 5) Start a cart from search terms (finds first matching product per term and adds all)

```bash
node "$SKILL_DIR/kroger.mjs" cart start --location-id 01400943 --terms "milk,eggs,bread" --qty 1 --modality DELIVERY
```

## Expected workflow when user asks for a cart

1. Ensure credentials are present.
2. Ensure customer OAuth token exists (run `oauth auth-url` / `oauth exchange-code` if needed).
3. Run location search (if location is unknown).
4. Run product search and confirm chosen products with user.
5. Run `cart add` or `cart start`.

## Notes

- The helper stores tokens at `~/.flux/kroger-session.json` by default.
- Output is JSON for reliable agent parsing.
- Cart actions can fail if cart scope/consent is missing; re-authorize with proper scopes.
