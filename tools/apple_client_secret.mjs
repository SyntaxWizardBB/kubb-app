// Generates the "Sign in with Apple" client secret JWT that Supabase's Apple
// OAuth provider expects in its "Secret Key (for OAuth)" field.
//
// This is ONLY for the web-redirect Apple login. It is NOT the APNs key (that
// one is uploaded raw to Firebase) and NOT the App Store Connect key.
//
// The JWT is ES256-signed and expires after at most 6 months — regenerate and
// re-paste into Supabase before it lapses, or Apple sign-in starts failing.
//
// Usage (nothing secret is stored in this file — values come from the env):
//   APPLE_TEAM_ID=ABCDE12345 \
//   APPLE_CLIENT_ID=ch.kubbclub.app.signin \   # the *Services ID* (= JWT `sub`)
//   APPLE_P8=./AuthKey_KEY1234567.p8 \
//     node tools/apple_client_secret.mjs
//
// APPLE_KEY_ID is auto-derived from the AuthKey_<KEYID>.p8 filename (override
// with APPLE_KEY_ID if your file is named differently). The JWT is printed and
// also written to APPLE_OUT (default: apple_client_secret.txt next to the .p8).

import { readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { sign } from 'node:crypto';

const teamId = process.env.APPLE_TEAM_ID;
const clientId = process.env.APPLE_CLIENT_ID;
const p8Path = process.env.APPLE_P8;

// Apple names the download AuthKey_<KEYID>.p8 — pull the Key ID from there.
const keyId =
  process.env.APPLE_KEY_ID ??
  (p8Path ? basename(p8Path).match(/AuthKey_([A-Z0-9]+)\.p8/i)?.[1] : undefined);

const outPath =
  process.env.APPLE_OUT ??
  (p8Path ? join(dirname(p8Path), 'apple_client_secret.txt') : undefined);

if (!teamId || !clientId || !p8Path || !keyId || !outPath) {
  console.error(
    'Missing input. Need APPLE_TEAM_ID, APPLE_CLIENT_ID, APPLE_P8 ' +
      '(+ APPLE_KEY_ID if not in the filename).',
  );
  process.exit(1);
}

const privateKey = readFileSync(p8Path, 'utf8');
const now = Math.floor(Date.now() / 1000);

const header = { alg: 'ES256', kid: keyId };
const payload = {
  iss: teamId,
  iat: now,
  exp: now + 86400 * 180, // 180 days — safely under Apple's 6-month ceiling
  aud: 'https://appleid.apple.com',
  sub: clientId,
};

const b64 = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
const signingInput = `${b64(header)}.${b64(payload)}`;

// ES256 for JOSE needs the raw R||S signature, NOT OpenSSL's default DER.
const signature = sign('sha256', Buffer.from(signingInput), {
  key: privateKey,
  dsaEncoding: 'ieee-p1363',
}).toString('base64url');

const jwt = `${signingInput}.${signature}`;
writeFileSync(outPath, `${jwt}\n`);
const expDate = new Date(payload.exp * 1000).toISOString().slice(0, 10);
console.log(jwt);
console.error(`\n→ written to ${outPath}\n→ expires ${expDate} (regenerate before then)`);
