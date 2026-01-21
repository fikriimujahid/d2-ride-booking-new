import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Signer } from '@aws-sdk/rds-signer';
import { createPool, Pool, PoolConnection } from 'mysql2/promise';
import { existsSync, readFileSync } from 'node:fs';
import { JsonLogger } from '../logging/json-logger.service';

/**
 * DatabaseService connects to MySQL using IAM auth tokens (no static passwords).
 * Token lifetime is ~15 minutes; mysql2 calls the auth plugin per-connection,
 * so a fresh token is requested transparently whenever the pool hands out a
 * connection. TLS is enabled to keep traffic encrypted in-flight.
 */
@Injectable()
export class DatabaseService implements OnModuleInit, OnModuleDestroy {
  private pool?: Pool;
  private signer?: Signer;
  private static readonly identifierPattern = /^[A-Za-z0-9_]+$/;

  constructor(private readonly config: ConfigService, private readonly logger: JsonLogger) {}

  async onModuleInit() {
    const host = this.config.get<string>('DB_HOST');
    const user = this.config.get<string>('DB_USER');
    const database = this.config.get<string>('DB_NAME');

    if (!host || !user || !database) {
      this.logger.warn('Database configuration missing; pool not created');
      return;
    }

    const port = Number(this.config.get<number>('DB_PORT') ?? 3306);
    const region = this.config.get<string>('AWS_REGION') ?? '';
    const password = this.config.get<string>('DB_PASSWORD');

    const sslConfig = this.buildSslConfig();

    // Local dev: use password-based auth if DB_PASSWORD is set
    // Production: use IAM auth (no password)
    const useIamAuth = !password;

    if (useIamAuth) {
      if (!sslConfig) {
        throw new Error('DB_SSL=false is not allowed when using IAM DB authentication (TLS is required)');
      }
      // signer produces short-lived auth tokens tied to IAM identity of the EC2 role
      this.signer = new Signer({
        hostname: host,
        port,
        username: user,
        region
      });

      this.pool = createPool({
        host,
        port,
        user,
        database,
        ssl: sslConfig, // TLS required for IAM auth
        authPlugins: {
          // mysql_clear_password is used by IAM auth. The plugin is invoked per connection,
          // so a new token is generated automatically before MySQL handshakes, keeping it fresh.
          mysql_clear_password: () => async () => `${await this.getAuthToken()}\0`
        }
      });

      this.logger.log('Database pool initialized with IAM auth token flow', { host, port, database });
    } else {
      // Password-based auth for local development
      this.pool = createPool({
        host,
        port,
        user,
        password,
        database,
        ...(sslConfig ? { ssl: sslConfig } : {})
      });

      this.logger.log('Database pool initialized with password auth (local dev)', { host, port, database });
    }
  }

  private buildSslConfig(): { rejectUnauthorized: boolean; ca?: string } | undefined {
    // Default: enable TLS with strict verification.
    // If you see "self-signed certificate in certificate chain", either:
    // - provide the correct CA bundle via DB_SSL_CA_PATH / DB_SSL_CA_B64, or
    // - (dev only) set DB_SSL_REJECT_UNAUTHORIZED=false to bypass verification.

    const sslEnabledRaw = this.config.get<string>('DB_SSL');
    const sslEnabled = sslEnabledRaw ? sslEnabledRaw.toLowerCase() !== 'false' : true;
    if (!sslEnabled) {
      return undefined;
    }

    const rejectRaw = this.config.get<string>('DB_SSL_REJECT_UNAUTHORIZED');
    const rejectUnauthorized = rejectRaw ? rejectRaw.toLowerCase() !== 'false' : true;

    const rawCaPath = (this.config.get<string>('DB_SSL_CA_PATH') ?? '').trim();
    const rawCaB64 = (this.config.get<string>('DB_SSL_CA_B64') ?? '').trim();

    // Guard against accidentally setting these vars as booleans in CI/CD (e.g. "true").
    // In that case, treat it as "not provided" and fall back to system CA bundle.
    const caPath = rawCaPath && rawCaPath !== 'true' && rawCaPath !== 'false' ? rawCaPath : '';
    const caB64 = rawCaB64 && rawCaB64 !== 'true' && rawCaB64 !== 'false' ? rawCaB64 : '';

    let ca: string | undefined;
    if (caPath) {
      try {
        ca = readFileSync(caPath, 'utf8');
      } catch (error) {
        this.logger.warn('Failed to read DB SSL CA file; continuing without custom CA', {
          caPath,
          error: (error as Error).message
        });
      }
    } else if (caB64) {
      try {
        ca = Buffer.from(caB64, 'base64').toString('utf8');
      } catch (error) {
        this.logger.warn('Failed to decode DB_SSL_CA_B64; continuing without custom CA', {
          error: (error as Error).message
        });
      }
    } else {
      // If no explicit CA is provided, try the system CA bundle.
      // This helps in environments where the DB uses a CA not present in Node's bundled CA set.
      const systemCaCandidates = [
        // Amazon Linux 2023
        '/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem',
        // Amazon Linux 2 / RHEL family
        '/etc/pki/tls/certs/ca-bundle.crt',
        // Debian/Ubuntu
        '/etc/ssl/certs/ca-certificates.crt',
        // Some distros
        '/etc/ssl/certs/ca-bundle.crt'
      ];

      const systemCaPath = systemCaCandidates.find((p) => existsSync(p));
      if (systemCaPath) {
        try {
          ca = readFileSync(systemCaPath, 'utf8');
          this.logger.log('Using system CA bundle for DB TLS', { systemCaPath });
        } catch (error) {
          this.logger.warn('Failed to read system CA bundle; continuing without custom CA', {
            systemCaPath,
            error: (error as Error).message
          });
        }
      }
    }

    if (!rejectUnauthorized) {
      this.logger.warn('DB TLS verification is disabled (DB_SSL_REJECT_UNAUTHORIZED=false)');
    }

    return ca ? { rejectUnauthorized, ca } : { rejectUnauthorized };
  }

  async onModuleDestroy() {
    if (this.pool) {
      await this.pool.end();
    }
  }

  private async getAuthToken(): Promise<string> {
    if (!this.signer) {
      throw new Error('RDS signer not initialized');
    }
    const token = await this.signer.getAuthToken();
    this.logger.log('Generated IAM DB auth token', { expiresInMinutes: 15 });
    return token;
  }

  async getConnection(): Promise<PoolConnection> {
    if (!this.pool) {
      throw new Error('Database pool is not initialized');
    }
    return this.pool.getConnection();
  }

  private static assertSafeIdentifier(identifier: string) {
    if (!DatabaseService.identifierPattern.test(identifier) || identifier.includes('`')) {
      throw new Error(`Unsafe SQL identifier: ${identifier}`);
    }
  }

  private static toBacktickedIdentifier(identifier: string): string {
    DatabaseService.assertSafeIdentifier(identifier);
    return `\`${identifier}\``;
  }

  private static templateToSql(strings: TemplateStringsArray, valueCount: number): string {
    let sql = '';
    for (let i = 0; i < strings.length; i++) {
      sql += strings[i];
      if (i < valueCount) {
        sql += '?';
      }
    }
    return sql;
  }

  // Tagged-template SQL helper. Interpolations become prepared-statement parameters.
  // Usage: await db.sql`SELECT * FROM t WHERE id = ${id}`
  async sql<T = unknown>(strings: TemplateStringsArray, ...params: unknown[]): Promise<T> {
    const sql = DatabaseService.templateToSql(strings, params.length);
    const connection = await this.getConnection();
    try {
      // Safe by construction: SQL text is derived from a tagged template literal and values
      // are passed separately as prepared-statement parameters ("?").
      const [rows] = await connection.query(sql, params); // nosemgrep: javascript.lang.security.audit.sqli.node-mysql-sqli.node-mysql-sqli
      return rows as T;
    } finally {
      connection.release();
    }
  }

  // Safe UPDATE builder that validates identifiers and always parameterizes values.
  async updateByKey(
    table: string,
    keyColumn: string,
    keyValue: unknown,
    updates: Record<string, unknown>,
    allowedColumns: readonly string[]
  ): Promise<void> {
    const updateEntries = Object.entries(updates).filter(([, v]) => v !== undefined);
    if (updateEntries.length === 0) {
      return;
    }

    DatabaseService.assertSafeIdentifier(table);
    DatabaseService.assertSafeIdentifier(keyColumn);

    const allowed = new Set(allowedColumns);
    for (const col of allowedColumns) {
      DatabaseService.assertSafeIdentifier(col);
    }

    const setClauses: string[] = [];
    const params: unknown[] = [];

    for (const [column, value] of updateEntries) {
      if (!allowed.has(column)) {
        throw new Error(`Disallowed update column: ${column}`);
      }
      DatabaseService.assertSafeIdentifier(column);
      setClauses.push(`${DatabaseService.toBacktickedIdentifier(column)} = ?`);
      params.push(value);
    }

    params.push(keyValue);

    const sql = `UPDATE ${DatabaseService.toBacktickedIdentifier(table)} SET ${setClauses.join(
      ', '
    )} WHERE ${DatabaseService.toBacktickedIdentifier(keyColumn)} = ?`;

    const connection = await this.getConnection();
    try {
      // Safe: identifiers are validated/escaped and all values are parameterized.
      await connection.query(sql, params); // nosemgrep: javascript.lang.security.audit.sqli.node-mysql-sqli.node-mysql-sqli
    } finally {
      connection.release();
    }
  }
}
