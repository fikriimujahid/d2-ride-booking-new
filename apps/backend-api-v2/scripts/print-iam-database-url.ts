import { Signer } from '@aws-sdk/rds-signer';

function mustGet(name: string): string {
  const value = process.env[name];
  if (!value || value.trim().length === 0) {
    throw new Error(`Missing env var: ${name}`);
  }
  return value.trim();
}

function getRegion(): string {
  return (
    process.env.DB_IAM_REGION?.trim() ||
    process.env.AWS_REGION?.trim() ||
    process.env.AWS_DEFAULT_REGION?.trim() ||
    process.env.COGNITO_REGION?.trim() ||
    ''
  );
}

function parseBoolean(value: unknown, defaultValue: boolean): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value !== 'string') return defaultValue;

  const normalized = value.trim().toLowerCase();
  if (normalized === 'true' || normalized === '1' || normalized === 'yes') return true;
  if (normalized === 'false' || normalized === '0' || normalized === 'no') return false;
  return defaultValue;
}

async function main() {
  const host = mustGet('DB_HOST');
  const port = Number(process.env.DB_PORT ?? '3306');
  const username = mustGet('DB_USER');
  const dbName = mustGet('DB_NAME');
  const region = getRegion();

  if (!region) {
    throw new Error('Missing region. Set DB_IAM_REGION or AWS_REGION.');
  }

  const signer = new Signer({ hostname: host, port, username, region });
  const token = await signer.getAuthToken();

  const requireSsl = parseBoolean(process.env.DB_IAM_REQUIRE_SSL, true);
  const query = requireSsl ? '?ssl=true' : '';

  // IMPORTANT: This prints a URL containing a secret token.
  // Use it only to set DATABASE_URL for Prisma CLI (migrate/seed) in a secure environment.
  const url = `mysql://${encodeURIComponent(username)}:${encodeURIComponent(token)}@${host}:${port}/${dbName}${query}`;
  process.stdout.write(url);
}

main().catch((err: unknown) => {
  // eslint-disable-next-line no-console
  console.error(err);
  process.exitCode = 1;
});
