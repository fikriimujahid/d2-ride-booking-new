import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaClient } from '@prisma/client';
import { PrismaMariaDb } from '@prisma/adapter-mariadb';
import { Signer } from '@aws-sdk/rds-signer';

type DbAuthMode = 'static' | 'iam';

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function mustGetNonEmpty(config: ConfigService, key: string): string {
  const value = config.get<string>(key);
  if (!isNonEmptyString(value)) throw new Error(`Missing required env var: ${key}`);
  return value.trim();
}

function getRegion(config: ConfigService): string {
  const region =
    config.get<string>('DB_IAM_REGION') ??
    config.get<string>('AWS_REGION') ??
    config.get<string>('AWS_DEFAULT_REGION') ??
    config.get<string>('COGNITO_REGION');
  return isNonEmptyString(region) ? region.trim() : '';
}

function parsePort(value: string | undefined, defaultPort: number): number {
  const port = value ? Number(value) : defaultPort;
  return Number.isFinite(port) && port > 0 ? port : defaultPort;
}

function parseBoolean(value: unknown, defaultValue: boolean): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value !== 'string') return defaultValue;

  const normalized = value.trim().toLowerCase();
  if (normalized === 'true' || normalized === '1' || normalized === 'yes') return true;
  if (normalized === 'false' || normalized === '0' || normalized === 'no') return false;
  return defaultValue;
}

@Injectable()
export class PrismaService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PrismaService.name);
  private prisma?: PrismaClient;

  private refreshTimer?: ReturnType<typeof setInterval>;
  private refreshInFlight?: Promise<void>;

  constructor(private readonly config: ConfigService) {
  }

  // Expose only the parts of PrismaClient currently used by this codebase.
  get adminUser(): PrismaClient['adminUser'] {
    if (!this.prisma) throw new Error('PrismaService not initialized (missing DB configuration).');
    return this.prisma.adminUser;
  }
  get role(): PrismaClient['role'] {
    if (!this.prisma) throw new Error('PrismaService not initialized (missing DB configuration).');
    return this.prisma.role;
  }
  get permission(): PrismaClient['permission'] {
    if (!this.prisma) throw new Error('PrismaService not initialized (missing DB configuration).');
    return this.prisma.permission;
  }
  get adminUserRole(): PrismaClient['adminUserRole'] {
    if (!this.prisma) throw new Error('PrismaService not initialized (missing DB configuration).');
    return this.prisma.adminUserRole;
  }
  get rolePermission(): PrismaClient['rolePermission'] {
    if (!this.prisma) throw new Error('PrismaService not initialized (missing DB configuration).');
    return this.prisma.rolePermission;
  }
  get adminAuditLog(): PrismaClient['adminAuditLog'] {
    if (!this.prisma) throw new Error('PrismaService not initialized (missing DB configuration).');
    return this.prisma.adminAuditLog;
  }

  $transaction(...args: Parameters<PrismaClient['$transaction']>) {
    if (!this.prisma) throw new Error('PrismaService not initialized (missing DB configuration).');
    return this.prisma.$transaction(...args);
  }

  private getAuthMode(): DbAuthMode {
    const mode = this.config.get<string>('DB_AUTH_MODE')?.trim().toLowerCase();
    return mode === 'iam' ? 'iam' : 'static';
  }

  private isStaticConfigured(): boolean {
    return isNonEmptyString(this.config.get<string>('DATABASE_URL'));
  }

  private isIamConfigured(): boolean {
    const hostOk = isNonEmptyString(this.config.get<string>('DB_HOST'));
    const nameOk = isNonEmptyString(this.config.get<string>('DB_NAME'));
    const userOk = isNonEmptyString(this.config.get<string>('DB_USER'));
    const regionOk = isNonEmptyString(getRegion(this.config));
    return hostOk && nameOk && userOk && regionOk;
  }

  private async createClient(): Promise<PrismaClient> {
    const mode = this.getAuthMode();

    if (mode === 'static') {
      const url = mustGetNonEmpty(this.config, 'DATABASE_URL');
      return new PrismaClient({ adapter: new PrismaMariaDb(url) });
    }

    const host = mustGetNonEmpty(this.config, 'DB_HOST');
    const dbName = mustGetNonEmpty(this.config, 'DB_NAME');
    const username = mustGetNonEmpty(this.config, 'DB_USER');
    const port = parsePort(this.config.get<string>('DB_PORT'), 3306);

    const region = getRegion(this.config);
    if (!region) throw new Error('Missing region for IAM DB auth. Set DB_IAM_REGION or AWS_REGION.');

    const signer = new Signer({ hostname: host, port, username, region });
    const token = await signer.getAuthToken();

    // RDS MySQL IAM auth requires TLS in most setups.
    const requireSsl = parseBoolean(this.config.get('DB_IAM_REQUIRE_SSL'), true);
    const query = requireSsl ? '?ssl=true' : '';

    // Token is a password-equivalent secret. Never log it.
    const url = `mysql://${encodeURIComponent(username)}:${encodeURIComponent(token)}@${host}:${port}/${dbName}${query}`;
    return new PrismaClient({ adapter: new PrismaMariaDb(url) });
  }

  private async refreshClient(reason: 'timer' | 'startup'): Promise<void> {
    if (this.refreshInFlight) return this.refreshInFlight;

    this.refreshInFlight = (async () => {
      const next = await this.createClient();
      await next.$connect();

      const previous = this.prisma;
      this.prisma = next;

      if (previous) await previous.$disconnect();

      if (reason === 'timer') {
        this.logger.debug('Refreshed Prisma client (IAM token rotation).');
      }
    })().finally(() => {
      this.refreshInFlight = undefined;
    });

    return this.refreshInFlight;
  }

  async onModuleInit(): Promise<void> {
    // Allow Phase A-only runs without a database.
    const mode = this.getAuthMode();
    if (mode === 'static' && !this.isStaticConfigured()) {
      this.logger.warn('DATABASE_URL is not set; database features will be unavailable.');
      return;
    }
    if (mode === 'iam' && !this.isIamConfigured()) {
      this.logger.warn(
        'DB_AUTH_MODE=iam but DB_HOST/DB_USER/DB_NAME/region are not fully set; database features will be unavailable.'
      );
      return;
    }

    // Create the right client and connect.
    await this.refreshClient('startup');

    // IAM tokens are short-lived; refresh the client periodically so new connections use fresh tokens.
    if (mode === 'iam') {
      const refreshSeconds = parsePort(this.config.get<string>('DB_IAM_TOKEN_REFRESH_SECONDS'), 600);

      // Disable refresh only if explicitly set to 0.
      if (refreshSeconds > 0) {
        this.refreshTimer = setInterval(() => {
          void this.refreshClient('timer');
        }, refreshSeconds * 1000);
        this.refreshTimer.unref?.();
      }
    }
  }

  async onModuleDestroy(): Promise<void> {
    if (this.refreshTimer) clearInterval(this.refreshTimer);
    if (this.prisma) await this.prisma.$disconnect();
  }
}
