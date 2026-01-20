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

  // Helper to run safe queries when business logic arrives; keeps future code DRY.
  async query<T = unknown>(sql: string, params?: unknown[]): Promise<T> {
    const connection = await this.getConnection();
    try {
      const [rows] = await connection.query(sql, params);
      return rows as T;
    } finally {
      connection.release();
    }
  }
}
