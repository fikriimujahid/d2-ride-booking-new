import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Signer } from '@aws-sdk/rds-signer';
import { createPool, Pool, PoolConnection } from 'mysql2/promise';
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

    // Local dev: use password-based auth if DB_PASSWORD is set
    // Production: use IAM auth (no password)
    const useIamAuth = !password;

    if (useIamAuth) {
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
        ssl: { rejectUnauthorized: true }, // enforce TLS; Amazon CA is trusted by Node runtime
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
        database
      });

      this.logger.log('Database pool initialized with password auth (local dev)', { host, port, database });
    }
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
      const [rows] = await connection.execute(sql, params); // nosemgrep: javascript.lang.security.audit.sqli.node-mysql-sqli.node-mysql-sqli
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
      await connection.execute(sql, params); // nosemgrep: javascript.lang.security.audit.sqli.node-mysql-sqli.node-mysql-sqli
    } finally {
      connection.release();
    }
  }
}
