#!/usr/bin/env node

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';

const API_BASE = process.env.KROGER_API_BASE || 'https://api.kroger.com';
const AUTHORIZE_URL = `${API_BASE}/v1/connect/oauth2/authorize`;
const TOKEN_URL = `${API_BASE}/v1/connect/oauth2/token`;
const CART_PATH = process.env.KROGER_CART_PATH || '/v1/cart/add';
const TOKEN_STORE_PATH = process.env.KROGER_TOKEN_STORE
  || path.join(os.homedir(), '.flux', 'kroger-session.json');

function fail(message, extra = {}) {
  const payload = { ok: false, error: message, ...extra };
  process.stderr.write(`${JSON.stringify(payload, null, 2)}\n`);
  process.exit(1);
}

function printJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function nowSeconds() {
  return Math.floor(Date.now() / 1000);
}

function parseArgs(argv) {
  const positional = [];
  const flags = {};

  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (!a.startsWith('--')) {
      positional.push(a);
      continue;
    }

    const without = a.slice(2);
    const eqIdx = without.indexOf('=');
    if (eqIdx !== -1) {
      const k = without.slice(0, eqIdx);
      const v = without.slice(eqIdx + 1);
      flags[k] = v;
      continue;
    }

    const k = without;
    const maybe = argv[i + 1];
    if (!maybe || maybe.startsWith('--')) {
      flags[k] = true;
      continue;
    }

    flags[k] = maybe;
    i += 1;
  }

  return { positional, flags };
}

function usage() {
  return [
    'Kroger skill helper CLI',
    '',
    'Required env:',
    '  KROGER_CLIENT_ID',
    '  KROGER_CLIENT_SECRET',
    'Optional env:',
    '  KROGER_REDIRECT_URI (default: http://localhost:8765/callback)',
    '  KROGER_CLIENT_SCOPE (default: product.compact location.compact)',
    '  KROGER_API_BASE (default: https://api.kroger.com)',
    '  KROGER_CART_PATH (default: /v1/cart/add)',
    '  KROGER_TOKEN_STORE (default: ~/.flux/kroger-session.json)',
    '',
    'Commands:',
    '  help',
    '  oauth auth-url [--scopes "cart.basic profile.compact product.compact"] [--state abc] [--open]',
    '  oauth exchange-code --code <authorization_code> [--redirect-uri <uri>]',
    '  oauth refresh',
    '  token client [--scope "product.compact location.compact"] [--force]',
    '  locations search (--zip <zip> | --lat <lat> --lon <lon>) [--radius 10] [--limit 10] [--chain KROGER] [--department 09]',
    '  products search --term "milk" [--location-id 01400943] [--limit 10] [--start 1] [--fulfillment csp] [--brand Kroger]',
    '  cart add --upc <13_digit_upc> [--qty 1] [--modality DELIVERY]',
    '  cart add --items-json <json_array>',
    '  cart start --location-id <id> --terms "milk,eggs,bread" [--qty 1] [--modality DELIVERY] [--limit-per-term 5]',
    '',
    'Output is JSON so agents can parse results.',
  ].join('\n');
}

async function ensureDir(filePath) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
}

async function loadSession() {
  try {
    const raw = await fs.readFile(TOKEN_STORE_PATH, 'utf8');
    return JSON.parse(raw);
  } catch {
    return {};
  }
}

async function saveSession(session) {
  await ensureDir(TOKEN_STORE_PATH);
  await fs.writeFile(TOKEN_STORE_PATH, JSON.stringify(session, null, 2), { mode: 0o600 });
}

function requiredEnv(name) {
  const value = process.env[name];
  if (!value || !value.trim()) {
    fail(`Missing required environment variable: ${name}`);
  }
  return value.trim();
}

function getClientCredentials() {
  const clientId = requiredEnv('KROGER_CLIENT_ID');
  const clientSecret = requiredEnv('KROGER_CLIENT_SECRET');
  return { clientId, clientSecret };
}

function defaultRedirectUri() {
  return (process.env.KROGER_REDIRECT_URI || 'http://localhost:8765/callback').trim();
}

function defaultClientScope() {
  return (process.env.KROGER_CLIENT_SCOPE || 'product.compact location.compact').trim();
}

function basicAuthHeader(clientId, clientSecret) {
  const base = Buffer.from(`${clientId}:${clientSecret}`, 'utf8').toString('base64');
  return `Basic ${base}`;
}

async function oauthTokenRequest(bodyParams, includeBasicAuth = true) {
  const { clientId, clientSecret } = getClientCredentials();
  const headers = {
    'Content-Type': 'application/x-www-form-urlencoded',
    Accept: 'application/json',
  };

  if (includeBasicAuth) {
    headers.Authorization = basicAuthHeader(clientId, clientSecret);
  }

  const body = new URLSearchParams();
  for (const [k, v] of Object.entries(bodyParams)) {
    if (v == null) continue;
    body.set(k, String(v));
  }

  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers,
    body: body.toString(),
  });

  const raw = await res.text();
  let json;
  try {
    json = raw ? JSON.parse(raw) : {};
  } catch {
    json = { raw };
  }

  if (!res.ok) {
    fail('Token request failed', { status: res.status, response: json });
  }

  return json;
}

function tokenExpiryEpoch(expiresIn) {
  const n = Number(expiresIn);
  if (!Number.isFinite(n) || n <= 0) return null;
  return nowSeconds() + n;
}

function tokenStillValid(expiresAtEpoch) {
  if (!expiresAtEpoch) return false;
  return Number(expiresAtEpoch) - 60 > nowSeconds();
}

async function getClientAccessToken({ force = false, scope } = {}) {
  const effectiveScope = (scope || defaultClientScope()).trim();
  const session = await loadSession();

  if (!force && session.client && session.client.scope === effectiveScope && tokenStillValid(session.client.expiresAtEpoch)) {
    return {
      token: session.client.accessToken,
      source: 'cache',
      scope: effectiveScope,
      expiresAtEpoch: session.client.expiresAtEpoch,
    };
  }

  const token = await oauthTokenRequest({
    grant_type: 'client_credentials',
    scope: effectiveScope,
  });

  session.client = {
    accessToken: token.access_token,
    tokenType: token.token_type,
    expiresIn: token.expires_in,
    expiresAtEpoch: tokenExpiryEpoch(token.expires_in),
    scope: effectiveScope,
    receivedAtEpoch: nowSeconds(),
  };
  await saveSession(session);

  return {
    token: session.client.accessToken,
    source: 'network',
    scope: effectiveScope,
    expiresAtEpoch: session.client.expiresAtEpoch,
  };
}

async function refreshCustomerAccessToken(refreshToken) {
  const token = await oauthTokenRequest({
    grant_type: 'refresh_token',
    refresh_token: refreshToken,
  }, true);

  const session = await loadSession();
  session.customer = {
    accessToken: token.access_token,
    refreshToken: token.refresh_token || refreshToken,
    tokenType: token.token_type,
    expiresIn: token.expires_in,
    expiresAtEpoch: tokenExpiryEpoch(token.expires_in),
    scope: token.scope || session.customer?.scope,
    receivedAtEpoch: nowSeconds(),
  };
  await saveSession(session);
  return session.customer;
}

async function getCustomerAccessToken() {
  const session = await loadSession();
  const customer = session.customer;

  if (customer?.accessToken && tokenStillValid(customer.expiresAtEpoch)) {
    return { token: customer.accessToken, source: 'cache', refreshed: false };
  }

  if (customer?.refreshToken) {
    const next = await refreshCustomerAccessToken(customer.refreshToken);
    return { token: next.accessToken, source: 'refresh', refreshed: true };
  }

  fail('No customer token available. Run `oauth auth-url` then `oauth exchange-code` first.');
}

async function apiRequest({
  token,
  method = 'GET',
  path: apiPath,
  query,
  body,
}) {
  const url = new URL(apiPath, API_BASE);
  if (query) {
    Object.entries(query).forEach(([k, v]) => {
      if (v == null || v === '') return;
      url.searchParams.set(k, String(v));
    });
  }

  const headers = {
    Accept: 'application/json',
    Authorization: `Bearer ${token}`,
  };

  let reqBody;
  if (body != null) {
    headers['Content-Type'] = 'application/json';
    reqBody = JSON.stringify(body);
  }

  const res = await fetch(url, {
    method,
    headers,
    body: reqBody,
  });

  const raw = await res.text();
  let json;
  try {
    json = raw ? JSON.parse(raw) : {};
  } catch {
    json = { raw };
  }

  return {
    ok: res.ok,
    status: res.status,
    url: url.toString(),
    data: json,
  };
}

function asNumber(value, name) {
  const n = Number(value);
  if (!Number.isFinite(n)) {
    fail(`Expected numeric value for --${name}`, { value });
  }
  return n;
}

function parseItemsJson(raw) {
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    fail('Failed to parse --items-json as JSON', { details: String(err) });
  }

  const items = Array.isArray(parsed) ? parsed : parsed?.items;
  if (!Array.isArray(items) || items.length === 0) {
    fail('items-json must be a non-empty array or an object with an `items` array');
  }

  return items.map((item) => ({
    upc: String(item.upc ?? '').trim(),
    quantity: Number(item.quantity ?? 1),
    modality: String(item.modality ?? 'DELIVERY').toUpperCase(),
    allowSubstitutes: item.allowSubstitutes == null ? undefined : Boolean(item.allowSubstitutes),
    specialInstructions: item.specialInstructions == null ? undefined : String(item.specialInstructions),
  }));
}

function pickProductUpc(product) {
  if (!product || typeof product !== 'object') return null;

  const direct = product.upc || product.productId;
  if (typeof direct === 'string' && direct.trim()) return direct.trim();

  if (Array.isArray(product.items) && product.items.length > 0) {
    const item0 = product.items[0];
    const fromItem = item0?.itemId || item0?.upc;
    if (typeof fromItem === 'string' && fromItem.trim()) return fromItem.trim();
  }

  return null;
}

function maybeOpen(url) {
  return new Promise((resolve) => {
    const child = spawn('open', [url], { stdio: 'ignore', detached: true });
    child.on('error', () => resolve(false));
    child.unref();
    resolve(true);
  });
}

async function cmdOAuth(positional, flags) {
  const action = positional[1];
  if (!action) {
    fail('Missing oauth action. Use `oauth auth-url`, `oauth exchange-code`, or `oauth refresh`.');
  }

  if (action === 'auth-url') {
    const { clientId } = getClientCredentials();
    const scopes = String(flags.scopes || 'cart.basic profile.compact product.compact').trim();
    const redirectUri = String(flags['redirect-uri'] || defaultRedirectUri()).trim();
    const state = flags.state ? String(flags.state) : undefined;

    const url = new URL(AUTHORIZE_URL);
    url.searchParams.set('scope', scopes);
    url.searchParams.set('response_type', 'code');
    url.searchParams.set('client_id', clientId);
    url.searchParams.set('redirect_uri', redirectUri);
    if (state) url.searchParams.set('state', state);

    let opened = false;
    if (flags.open) {
      opened = await maybeOpen(url.toString());
    }

    printJson({
      ok: true,
      action: 'oauth.auth-url',
      authorizeUrl: url.toString(),
      scopes,
      redirectUri,
      opened,
      nextStep: 'After consent, run: kroger.mjs oauth exchange-code --code <code> --redirect-uri <same redirect uri>',
    });
    return;
  }

  if (action === 'exchange-code') {
    const code = String(flags.code || '').trim();
    if (!code) {
      fail('Missing --code for oauth exchange-code');
    }

    const redirectUri = String(flags['redirect-uri'] || defaultRedirectUri()).trim();
    const token = await oauthTokenRequest({
      grant_type: 'authorization_code',
      code,
      redirect_uri: redirectUri,
    });

    const session = await loadSession();
    session.customer = {
      accessToken: token.access_token,
      refreshToken: token.refresh_token,
      tokenType: token.token_type,
      expiresIn: token.expires_in,
      expiresAtEpoch: tokenExpiryEpoch(token.expires_in),
      scope: token.scope,
      receivedAtEpoch: nowSeconds(),
      redirectUri,
    };
    await saveSession(session);

    printJson({
      ok: true,
      action: 'oauth.exchange-code',
      tokenStoredAt: TOKEN_STORE_PATH,
      scope: session.customer.scope,
      expiresAtEpoch: session.customer.expiresAtEpoch,
      hasRefreshToken: Boolean(session.customer.refreshToken),
    });
    return;
  }

  if (action === 'refresh') {
    const session = await loadSession();
    const refreshToken = session.customer?.refreshToken;
    if (!refreshToken) {
      fail('No refresh token found. Run oauth auth-url + oauth exchange-code first.');
    }

    const customer = await refreshCustomerAccessToken(refreshToken);
    printJson({
      ok: true,
      action: 'oauth.refresh',
      scope: customer.scope,
      expiresAtEpoch: customer.expiresAtEpoch,
      tokenStoredAt: TOKEN_STORE_PATH,
    });
    return;
  }

  fail(`Unknown oauth action: ${action}`);
}

async function cmdToken(positional, flags) {
  const action = positional[1];
  if (action !== 'client') {
    fail('Unknown token action. Use `token client`.');
  }

  const scope = flags.scope ? String(flags.scope).trim() : undefined;
  const force = Boolean(flags.force);
  const res = await getClientAccessToken({ force, scope });
  printJson({
    ok: true,
    action: 'token.client',
    source: res.source,
    scope: res.scope,
    expiresAtEpoch: res.expiresAtEpoch,
    accessToken: res.token,
  });
}

async function cmdLocations(positional, flags) {
  const action = positional[1];
  if (action !== 'search') {
    fail('Unknown locations action. Use `locations search`.');
  }

  const query = {};
  if (flags.zip) {
    query['filter.zipCode.near'] = String(flags.zip).trim();
  } else if (flags.lat && flags.lon) {
    query['filter.lat.near'] = String(flags.lat).trim();
    query['filter.lon.near'] = String(flags.lon).trim();
  } else if (flags['lat-long']) {
    query['filter.latLong.near'] = String(flags['lat-long']).trim();
  }

  if (flags.radius != null) query['filter.radiusInMiles'] = asNumber(flags.radius, 'radius');
  if (flags.limit != null) query['filter.limit'] = asNumber(flags.limit, 'limit');
  if (flags.chain != null) query['filter.chain'] = String(flags.chain).trim();
  if (flags.department != null) query['filter.department'] = String(flags.department).trim();
  if (flags['location-id'] != null) query['filter.locationId'] = String(flags['location-id']).trim();

  const token = await getClientAccessToken({});
  const response = await apiRequest({
    token: token.token,
    path: '/v1/locations',
    query,
  });

  if (!response.ok) {
    fail('Kroger locations request failed', response);
  }

  const list = Array.isArray(response.data?.data) ? response.data.data : [];
  const simplified = list.map((loc) => ({
    locationId: loc.locationId,
    name: loc.name,
    chain: loc.chain,
    phone: loc.phone,
    address: loc.address,
    geolocation: loc.geolocation,
  }));

  printJson({
    ok: true,
    action: 'locations.search',
    requestUrl: response.url,
    count: simplified.length,
    locations: simplified,
    raw: response.data,
  });
}

async function cmdProducts(positional, flags) {
  const action = positional[1];
  if (action !== 'search') {
    fail('Unknown products action. Use `products search`.');
  }

  const term = String(flags.term || '').trim();
  const brand = String(flags.brand || '').trim();
  const productId = String(flags['product-id'] || '').trim();
  if (!term && !brand && !productId) {
    fail('products search requires one of --term, --brand, or --product-id');
  }

  const query = {};
  if (term) query['filter.term'] = term;
  if (brand) query['filter.brand'] = brand;
  if (productId) query['filter.productId'] = productId;
  if (flags['location-id']) query['filter.locationId'] = String(flags['location-id']).trim();
  if (flags.fulfillment) query['filter.fulfillment'] = String(flags.fulfillment).trim();
  if (flags.limit != null) query['filter.limit'] = asNumber(flags.limit, 'limit');
  if (flags.start != null) query['filter.start'] = asNumber(flags.start, 'start');

  const token = await getClientAccessToken({});
  const response = await apiRequest({
    token: token.token,
    path: '/v1/products',
    query,
  });

  if (!response.ok) {
    fail('Kroger products request failed', response);
  }

  const data = Array.isArray(response.data?.data) ? response.data.data : [];
  const simplified = data.map((p) => ({
    productId: p.productId,
    upc: p.upc,
    description: p.description,
    brand: p.brand,
    categories: p.categories,
    itemId: Array.isArray(p.items) && p.items[0] ? p.items[0].itemId : undefined,
    size: Array.isArray(p.items) && p.items[0] ? p.items[0].size : undefined,
    price: Array.isArray(p.items) && p.items[0] ? p.items[0].price : undefined,
    fulfillment: Array.isArray(p.items) && p.items[0] ? p.items[0].fulfillment : undefined,
  }));

  printJson({
    ok: true,
    action: 'products.search',
    requestUrl: response.url,
    count: simplified.length,
    products: simplified,
    raw: response.data,
  });
}

function normalizeCartItems(items) {
  return items.map((item, idx) => {
    const upc = String(item.upc || '').trim();
    const quantity = Number(item.quantity ?? 1);
    const modality = String(item.modality || 'DELIVERY').toUpperCase();

    if (!upc) {
      fail(`Cart item at index ${idx} missing upc`);
    }
    if (!Number.isFinite(quantity) || quantity <= 0) {
      fail(`Cart item at index ${idx} has invalid quantity`, { quantity });
    }

    const out = { upc, quantity, modality };
    if (item.allowSubstitutes != null) out.allowSubstitutes = Boolean(item.allowSubstitutes);
    if (item.specialInstructions != null) out.specialInstructions = String(item.specialInstructions);
    return out;
  });
}

async function addToCart(items) {
  const normalizedItems = normalizeCartItems(items);
  const customer = await getCustomerAccessToken();

  const response = await apiRequest({
    token: customer.token,
    method: 'PUT',
    path: CART_PATH,
    body: { items: normalizedItems },
  });

  if (!response.ok) {
    fail('Kroger cart add request failed', response);
  }

  return {
    ok: true,
    action: 'cart.add',
    requestUrl: response.url,
    items: normalizedItems,
    response: response.data,
  };
}

async function cmdCart(positional, flags) {
  const action = positional[1];

  if (action === 'add') {
    let items;

    if (flags['items-json']) {
      items = parseItemsJson(String(flags['items-json']));
    } else {
      const upc = String(flags.upc || '').trim();
      if (!upc) {
        fail('cart add requires --upc or --items-json');
      }
      items = [{
        upc,
        quantity: Number(flags.qty ?? 1),
        modality: String(flags.modality ?? 'DELIVERY').toUpperCase(),
      }];
    }

    const result = await addToCart(items);
    printJson(result);
    return;
  }

  if (action === 'start') {
    const locationId = String(flags['location-id'] || '').trim();
    const termsRaw = String(flags.terms || '').trim();
    if (!locationId) {
      fail('cart start requires --location-id');
    }
    if (!termsRaw) {
      fail('cart start requires --terms (comma-separated)');
    }

    const qty = Number(flags.qty ?? 1);
    if (!Number.isFinite(qty) || qty <= 0) {
      fail('Invalid --qty', { qty });
    }

    const modality = String(flags.modality ?? 'DELIVERY').toUpperCase();
    const limitPerTerm = Number(flags['limit-per-term'] ?? 5);

    const token = await getClientAccessToken({});

    const terms = termsRaw
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);

    if (terms.length === 0) {
      fail('No valid terms provided for --terms');
    }

    const selected = [];
    const misses = [];

    for (const term of terms) {
      const response = await apiRequest({
        token: token.token,
        path: '/v1/products',
        query: {
          'filter.term': term,
          'filter.locationId': locationId,
          'filter.limit': limitPerTerm,
        },
      });

      if (!response.ok) {
        fail(`Product search failed for term: ${term}`, response);
      }

      const products = Array.isArray(response.data?.data) ? response.data.data : [];
      const first = products.find((p) => pickProductUpc(p));
      if (!first) {
        misses.push({ term, reason: 'No product with usable UPC found' });
        continue;
      }

      const upc = pickProductUpc(first);
      selected.push({
        term,
        upc,
        quantity: qty,
        modality,
        productId: first.productId,
        description: first.description,
        brand: first.brand,
      });
    }

    if (selected.length === 0) {
      fail('No products found for any requested term', { misses });
    }

    const cartResult = await addToCart(selected.map((s) => ({
      upc: s.upc,
      quantity: s.quantity,
      modality: s.modality,
    })));

    printJson({
      ok: true,
      action: 'cart.start',
      locationId,
      selected,
      misses,
      cart: cartResult,
    });
    return;
  }

  fail('Unknown cart action. Use `cart add` or `cart start`.');
}

async function main() {
  const { positional, flags } = parseArgs(process.argv.slice(2));
  const root = positional[0] || 'help';

  if (root === 'help' || root === '--help' || root === '-h') {
    process.stdout.write(`${usage()}\n`);
    return;
  }

  if (root === 'oauth') {
    await cmdOAuth(positional, flags);
    return;
  }

  if (root === 'token') {
    await cmdToken(positional, flags);
    return;
  }

  if (root === 'locations') {
    await cmdLocations(positional, flags);
    return;
  }

  if (root === 'products') {
    await cmdProducts(positional, flags);
    return;
  }

  if (root === 'cart') {
    await cmdCart(positional, flags);
    return;
  }

  fail(`Unknown command: ${root}`, { usage: usage() });
}

main().catch((err) => {
  fail('Unhandled error', { details: err instanceof Error ? err.message : String(err) });
});
