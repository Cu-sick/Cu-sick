#!/usr/bin/env node
/**
 * monarch-session.mjs — Playwright helper for Monarch Money session assurance.
 *
 * Commands:
 *   node monarch-session.mjs validate   # load storageState, check still logged in
 *   node monarch-session.mjs refresh    # validate; if stale, full re-auth (email+pw+TOTP)
 *
 * Configuration is passed via env vars (so secrets never hit the process arg list
 * / command history):
 *   MONARCH_EMAIL, MONARCH_PASSWORD, MONARCH_MFA_SECRET   (creds; MFA optional)
 *   MM_STATE_PATH        absolute path to the Playwright storageState JSON
 *   MM_SETTINGS_PATH     absolute path to settings.config.json (URLs + selectors)
 *   MM_HEADLESS          "true" | "false"   (default true)
 *
 * Output: a single JSON object on stdout describing the result. Exit code 0 on
 * success (session is usable), non-zero on failure.
 *
 * Dependencies: playwright (chromium). TOTP is computed locally with Node crypto —
 * no extra packages required.
 */

import { chromium } from 'playwright';
import { createHmac } from 'node:crypto';
import { readFileSync, existsSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

// ── helpers ────────────────────────────────────────────────────────────────

function out(obj, code = 0) {
  process.stdout.write(JSON.stringify(obj) + '\n');
  process.exit(code);
}

function loadSettings() {
  const p = process.env.MM_SETTINGS_PATH;
  if (!p || !existsSync(p)) {
    throw new Error(`settings.config.json not found (MM_SETTINGS_PATH=${p || 'unset'})`);
  }
  return JSON.parse(readFileSync(p, 'utf8'));
}

/** Base32 → Buffer (RFC 4648, no padding required). */
function base32ToBuffer(b32) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  const clean = (b32 || '').toUpperCase().replace(/[^A-Z2-7]/g, '');
  let bits = '';
  for (const c of clean) bits += alphabet.indexOf(c).toString(2).padStart(5, '0');
  const bytes = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) bytes.push(parseInt(bits.slice(i, i + 8), 2));
  return Buffer.from(bytes);
}

/** RFC 6238 TOTP (6 digits, 30s, SHA1). */
function totp(secret) {
  const key = base32ToBuffer(secret);
  const counter = Math.floor(Date.now() / 1000 / 30);
  const buf = Buffer.alloc(8);
  buf.writeBigInt64BE(BigInt(counter));
  const hmac = createHmac('sha1', key).update(buf).digest();
  const offset = hmac[hmac.length - 1] & 0x0f;
  const code =
    ((hmac[offset] & 0x7f) << 24) |
    ((hmac[offset + 1] & 0xff) << 16) |
    ((hmac[offset + 2] & 0xff) << 8) |
    (hmac[offset + 3] & 0xff);
  return (code % 1_000_000).toString().padStart(6, '0');
}

/** Try a list of selector candidates; return the first that resolves quickly. */
async function firstVisible(page, selectors, timeout = 4000) {
  for (const sel of selectors) {
    try {
      const loc = page.locator(sel).first();
      await loc.waitFor({ state: 'visible', timeout });
      return loc;
    } catch { /* try next */ }
  }
  return null;
}

async function isLoggedIn(page, settings) {
  // Logged in if an authenticated nav marker is present and we are NOT on /login.
  const url = page.url();
  if (url.includes('/login')) return false;
  const marker = await firstVisible(page, settings.monarch.selectors.loggedInMarker, 6000);
  return marker !== null;
}

// ── core ─────────────────────────────────────────────────────────────────

async function run() {
  const command = process.argv[2] || 'validate';
  const settings = loadSettings();
  const statePath = process.env.MM_STATE_PATH;
  const headless = (process.env.MM_HEADLESS ?? 'true').toLowerCase() !== 'false';

  if (!statePath) throw new Error('MM_STATE_PATH is required.');

  const navTimeout = settings.playwright?.navigationTimeoutMs ?? 45000;
  const hasState = existsSync(statePath);

  const browser = await chromium.launch({
    headless,
    slowMo: settings.playwright?.slowMoMs ?? 0,
  });
  const context = await browser.newContext({
    storageState: hasState ? statePath : undefined,
    userAgent: settings.playwright?.userAgent || undefined,
  });
  const page = await context.newPage();
  page.setDefaultNavigationTimeout(navTimeout);
  page.setDefaultTimeout(settings.playwright?.actionTimeoutMs ?? 15000);

  const result = {
    command,
    loggedIn: false,
    wasStale: null,
    action: 'none',          // none | validated | reauthenticated
    reauthAttempted: false,
    statePath,
    hadExistingState: hasState,
    error: null,
  };

  try {
    await page.goto(settings.monarch.appUrl, { waitUntil: 'domcontentloaded' });
    // Give the SPA a moment to either render the app or redirect to /login.
    await page.waitForLoadState('networkidle').catch(() => {});

    let loggedIn = await isLoggedIn(page, settings);
    result.wasStale = !loggedIn;

    if (loggedIn) {
      result.loggedIn = true;
      result.action = 'validated';
      await saveState(context, statePath); // refresh any rolling cookies
      await cleanup(browser);
      return out(result, 0);
    }

    if (command === 'validate') {
      // validate-only: report stale, do not re-auth
      result.loggedIn = false;
      await cleanup(browser);
      return out(result, 2); // exit 2 = stale (distinct from hard error)
    }

    // ── refresh: perform full re-authentication ──────────────────────────
    result.reauthAttempted = true;
    const email = process.env.MONARCH_EMAIL;
    const password = process.env.MONARCH_PASSWORD;
    const mfaSecret = process.env.MONARCH_MFA_SECRET;
    if (!email || !password) throw new Error('MONARCH_EMAIL / MONARCH_PASSWORD required for re-auth.');

    if (!page.url().includes('/login')) {
      await page.goto(settings.monarch.loginUrl, { waitUntil: 'domcontentloaded' });
    }

    const emailEl = await firstVisible(page, settings.monarch.selectors.emailInput, 10000);
    if (!emailEl) throw new Error('Email field not found on login page (selectors may be stale).');
    await emailEl.fill(email);

    const pwEl = await firstVisible(page, settings.monarch.selectors.passwordInput, 8000);
    if (!pwEl) throw new Error('Password field not found.');
    await pwEl.fill(password);

    const submitEl = await firstVisible(page, settings.monarch.selectors.submitButton, 8000);
    if (!submitEl) throw new Error('Submit button not found.');
    await submitEl.click();

    // Handle MFA if challenged.
    const mfaEl = await firstVisible(page, settings.monarch.selectors.mfaInput, 8000);
    if (mfaEl) {
      if (!mfaSecret) throw new Error('MFA challenge presented but MONARCH_MFA_SECRET is not set.');
      await mfaEl.fill(totp(mfaSecret));
      const mfaSubmit = await firstVisible(page, settings.monarch.selectors.mfaSubmit, 6000);
      if (mfaSubmit) await mfaSubmit.click();
    }

    await page.waitForLoadState('networkidle', { timeout: navTimeout }).catch(() => {});
    loggedIn = await isLoggedIn(page, settings);

    if (!loggedIn) throw new Error('Re-authentication did not reach an authenticated state.');

    result.loggedIn = true;
    result.action = 'reauthenticated';
    await saveState(context, statePath);
    await cleanup(browser);
    return out(result, 0);
  } catch (err) {
    result.error = err?.message || String(err);
    try { await cleanup(browser); } catch {}
    return out(result, 1);
  }
}

async function saveState(context, statePath) {
  mkdirSync(dirname(statePath), { recursive: true });
  await context.storageState({ path: statePath });
}

async function cleanup(browser) {
  await browser.close();
}

run().catch((err) => out({ command: process.argv[2] || 'validate', error: err?.message || String(err), loggedIn: false }, 1));
