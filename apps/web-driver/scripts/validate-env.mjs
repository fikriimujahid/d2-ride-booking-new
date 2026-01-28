import fs from 'node:fs';
import path from 'node:path';

function fail(message) {
  console.error(`ENV VALIDATION FAILED: ${message}`);
  process.exit(1);
}

function loadDotenvFile(filePath) {
  if (!fs.existsSync(filePath)) return;

  const content = fs.readFileSync(filePath, 'utf8');
  for (const line of content.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;

    const eq = trimmed.indexOf('=');
    if (eq <= 0) continue;

    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();

    // Strip surrounding quotes (common in CI secrets and local env files).
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    if (process.env[key] === undefined) process.env[key] = value;
  }
}

// Next.js loads .env automatically, but this script runs in plain Node.
loadDotenvFile(path.resolve(process.cwd(), '.env.local'));
loadDotenvFile(path.resolve(process.cwd(), '.env'));

function requireTrimmed(name) {
  const raw = process.env[name];
  const value = (raw ?? '').trim();
  if (!value) fail(`Missing ${name}.`);
  return value;
}

const userPoolId = requireTrimmed('NEXT_PUBLIC_COGNITO_USER_POOL_ID');
const clientId = requireTrimmed('NEXT_PUBLIC_COGNITO_CLIENT_ID');

if (userPoolId.includes('arn:') || userPoolId.includes('userpool/')) {
  fail(
    'NEXT_PUBLIC_COGNITO_USER_POOL_ID looks like an ARN. Use the raw pool id like "ap-southeast-1_XXXXXXXXX".'
  );
}

if (userPoolId.length > 55 || !/^[\w-]+_[0-9a-zA-Z]+$/.test(userPoolId)) {
  fail(
    'NEXT_PUBLIC_COGNITO_USER_POOL_ID must match "<region>_<id>" (example: "ap-southeast-1_XXXXXXXXX").'
  );
}

// Client ID is opaque but should not contain whitespace/quotes; trimming already handled.
if (/\s/.test(clientId)) {
  fail('NEXT_PUBLIC_COGNITO_CLIENT_ID contains whitespace (check for accidental newlines).');
}

console.log('ENV VALIDATION OK');
