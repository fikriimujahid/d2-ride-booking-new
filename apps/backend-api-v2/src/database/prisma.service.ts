// Import NestJS lifecycle hooks and decorators
import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
// Import ConfigService for reading environment variables
import { ConfigService } from '@nestjs/config';
// Import Prisma client for database operations
import { PrismaClient } from '@prisma/client';
// Import MariaDB adapter for Prisma (MySQL-compatible)
import { PrismaMariaDb } from '@prisma/adapter-mariadb';
// Import AWS RDS Signer for IAM database authentication
import { Signer } from '@aws-sdk/rds-signer';

// Database authentication mode: static connection string or IAM token-based
type DbAuthMode = 'static' | 'iam';

/**
 * Type guard to check if value is a non-empty string
 * @param value - Value to check
 * @returns true if value is a non-empty string after trimming
 */
function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

/**
 * Get required non-empty environment variable or throw error
 * @param config - ConfigService instance
 * @param key - Environment variable key
 * @returns Trimmed string value
 * @throws Error if value is missing or empty
 */
function mustGetNonEmpty(config: ConfigService, key: string): string {
  const value = config.get<string>(key);
  if (!isNonEmptyString(value)) throw new Error(`Missing required env var: ${key}`);
  return value.trim();
}

/**
 * Get AWS region from multiple possible environment variables
 * Checks in priority order: DB_IAM_REGION > AWS_REGION > AWS_DEFAULT_REGION > COGNITO_REGION
 * @param config - ConfigService instance
 * @returns Region string or empty string if not found
 */
function getRegion(config: ConfigService): string {
  const region =
    config.get<string>('DB_IAM_REGION') ??
    config.get<string>('AWS_REGION') ??
    config.get<string>('AWS_DEFAULT_REGION') ??
    config.get<string>('COGNITO_REGION');
  return isNonEmptyString(region) ? region.trim() : '';
}

/**
 * Parse port number from string with fallback to default
 * @param value - Port string from environment
 * @param defaultPort - Default port if parsing fails
 * @returns Valid positive port number
 */
function parsePort(value: string | undefined, defaultPort: number): number {
  const port = value ? Number(value) : defaultPort;
  return Number.isFinite(port) && port > 0 ? port : defaultPort;
}

/**
 * Parse boolean value from various string representations
 * Handles: 'true'/'false', '1'/'0', 'yes'/'no' (case-insensitive)
 * @param value - Value to parse
 * @param defaultValue - Default if parsing fails
 * @returns Parsed boolean value
 */
function parseBoolean(value: unknown, defaultValue: boolean): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value !== 'string') return defaultValue;

  const normalized = value.trim().toLowerCase();
  if (normalized === 'true' || normalized === '1' || normalized === 'yes') return true;
  if (normalized === 'false' || normalized === '0' || normalized === 'no') return false;
  return defaultValue;
}

/**
 * PrismaService - Database service managing Prisma ORM client lifecycle
 * Supports two authentication modes:
 * 1. Static: Traditional connection string (DATABASE_URL)
 * 2. IAM: AWS RDS IAM authentication with automatic token refresh
 * 
 * Features:
 * - Lazy initialization (allows Phase A without database)
 * - Automatic IAM token rotation for security
 * - Proper connection lifecycle management
 * - Typed model access with error handling
 */
@Injectable()
export class PrismaService implements OnModuleInit, OnModuleDestroy {
  // Logger for debugging and operational visibility
  private readonly logger = new Logger(PrismaService.name);
  // Lazily initialized Prisma client (undefined if DB not configured)
  private prisma?: PrismaClient;

  // Timer for periodic IAM token refresh
  private refreshTimer?: ReturnType<typeof setInterval>;
  // Promise to prevent concurrent refresh operations
  private refreshInFlight?: Promise<void>;

  /**
   * Constructor - injects ConfigService for reading environment variables
   * @param config - NestJS ConfigService
   */
  constructor(private readonly config: ConfigService) {
  }

  /**
   * Expose adminUser model access with lazy initialization check
   * @throws Error if PrismaService was not initialized (missing DB config)
   */
  get adminUser(): PrismaClient['adminUser'] {
    if (!this.prisma) throw new Error('PrismaService not initialized (missing DB configuration).');
    return this.prisma.adminUser;
  }
  
  /**
   * Expose role model access with lazy initialization check
   * @throws Error if PrismaService was not initialized
   */
  get role(): PrismaClient['role'] {
    if (!this.prisma) throw new Error('PrismaService not initialized (missing DB configuration).');
    return this.prisma.role;
  }
  
  /**
   * Expose permission model access with lazy initialization check
   * @throws Error if PrismaService was not initialized
   */
  get permission(): PrismaClient['permission'] {
    if (!this.prisma) throw new Error('PrismaService not initialized (missing DB configuration).');
    return this.prisma.permission;
  }
  
  /**
   * Expose adminUserRole junction table access with lazy initialization check
   * @throws Error if PrismaService was not initialized
   */
  get adminUserRole(): PrismaClient['adminUserRole'] {
    if (!this.prisma) throw new Error('PrismaService not initialized (missing DB configuration).');
    return this.prisma.adminUserRole;
  }
  
  /**
   * Expose rolePermission junction table access with lazy initialization check
   * @throws Error if PrismaService was not initialized
   */
  get rolePermission(): PrismaClient['rolePermission'] {
    if (!this.prisma) throw new Error('PrismaService not initialized (missing DB configuration).');
    return this.prisma.rolePermission;
  }
  
  /**
   * Expose adminAuditLog model access with lazy initialization check
   * @throws Error if PrismaService was not initialized
   */
  get adminAuditLog(): PrismaClient['adminAuditLog'] {
    if (!this.prisma) throw new Error('PrismaService not initialized (missing DB configuration).');
    return this.prisma.adminAuditLog;
  }

  /**
   * Expose Prisma transaction API with lazy initialization check
   * Allows running multiple operations atomically
   * @throws Error if PrismaService was not initialized
   */
  $transaction(...args: Parameters<PrismaClient['$transaction']>) {
    if (!this.prisma) throw new Error('PrismaService not initialized (missing DB configuration).');
    return this.prisma.$transaction(...args);
  }

  /**
   * Get configured database authentication mode
   * @returns 'iam' if explicitly set, otherwise 'static' (default)
   */
  private getAuthMode(): DbAuthMode {
    const mode = this.config.get<string>('DB_AUTH_MODE')?.trim().toLowerCase();
    return mode === 'iam' ? 'iam' : 'static';
  }

  /**
   * Check if static mode is properly configured
   * @returns true if DATABASE_URL environment variable is set
   */
  private isStaticConfigured(): boolean {
    return isNonEmptyString(this.config.get<string>('DATABASE_URL'));
  }

  /**
   * Check if IAM mode is properly configured
   * Requires DB_HOST, DB_USER, DB_NAME, and a region variable
   * @returns true if all required IAM configuration is present
   */
  private isIamConfigured(): boolean {
    const hostOk = isNonEmptyString(this.config.get<string>('DB_HOST'));
    const nameOk = isNonEmptyString(this.config.get<string>('DB_NAME'));
    const userOk = isNonEmptyString(this.config.get<string>('DB_USER'));
    const regionOk = isNonEmptyString(getRegion(this.config));
    return hostOk && nameOk && userOk && regionOk;
  }

  /**
   * Create a new PrismaClient instance based on configured authentication mode
   * 
   * Static mode: Uses DATABASE_URL connection string directly
   * IAM mode: Generates temporary AWS RDS IAM authentication token
   * 
   * @returns Promise resolving to configured PrismaClient instance
   * @throws Error if required configuration is missing
   */
  private async createClient(): Promise<PrismaClient> {
    const mode = this.getAuthMode();

    // Static mode: simple connection string
    if (mode === 'static') {
      const url = mustGetNonEmpty(this.config, 'DATABASE_URL');
      return new PrismaClient({ adapter: new PrismaMariaDb(url) });
    }

    // IAM mode: build connection string with temporary token
    const host = mustGetNonEmpty(this.config, 'DB_HOST');
    const dbName = mustGetNonEmpty(this.config, 'DB_NAME');
    const username = mustGetNonEmpty(this.config, 'DB_USER');
    const port = parsePort(this.config.get<string>('DB_PORT'), 3306);

    const region = getRegion(this.config);
    if (!region) throw new Error('Missing region for IAM DB auth. Set DB_IAM_REGION or AWS_REGION.');

    // Generate temporary IAM authentication token from AWS
    const signer = new Signer({ hostname: host, port, username, region });
    const token = await signer.getAuthToken();

    // RDS MySQL IAM auth requires TLS in most production setups
    const requireSsl = parseBoolean(this.config.get('DB_IAM_REQUIRE_SSL'), true);
    const query = requireSsl ? '?ssl=true' : '';

    // Build connection URL with token as password
    // Token is a password-equivalent secret - never log it for security
    const url = `mysql://${encodeURIComponent(username)}:${encodeURIComponent(token)}@${host}:${port}/${dbName}${query}`;
    return new PrismaClient({ adapter: new PrismaMariaDb(url) });
  }

  /**
   * Refresh Prisma client with new IAM token (for IAM mode)
   * Creates new client, connects it, swaps with old client, disconnects old one
   * Prevents concurrent refresh operations using a lock promise
   * 
   * @param reason - Why the refresh is happening ('timer' for scheduled, 'startup' for init)
   * @returns Promise that resolves when refresh is complete
   */
  private async refreshClient(reason: 'timer' | 'startup'): Promise<void> {
    // If refresh is already in progress, return existing promise (prevents race conditions)
    if (this.refreshInFlight) return this.refreshInFlight;

    // Create refresh operation promise
    this.refreshInFlight = (async () => {
      // Create new client with fresh IAM token
      const next = await this.createClient();
      // Establish connection to database
      await next.$connect();

      // Swap old client with new one atomically
      const previous = this.prisma;
      this.prisma = next;

      // Gracefully disconnect old client if it exists
      if (previous) await previous.$disconnect();

      // Log refresh for operational visibility (only for periodic refreshes)
      if (reason === 'timer') {
        this.logger.debug('Refreshed Prisma client (IAM token rotation).');
      }
    })().finally(() => {
      // Clear in-flight lock when operation completes
      this.refreshInFlight = undefined;
    });

    return this.refreshInFlight;
  }

  /**
   * NestJS lifecycle hook - called when module is initialized
   * Sets up database connection and IAM token refresh timer if needed
   * Allows graceful degradation: app can run without database for Phase A-only functionality
   */
  async onModuleInit(): Promise<void> {
    // Allow Phase A-only runs without a database (auth doesn't require DB)
    const mode = this.getAuthMode();
    
    // Check if static mode is configured
    if (mode === 'static' && !this.isStaticConfigured()) {
      this.logger.warn('DATABASE_URL is not set; database features will be unavailable.');
      return;  // Exit early, no database connection
    }
    
    // Check if IAM mode is configured
    if (mode === 'iam' && !this.isIamConfigured()) {
      this.logger.warn(
        'DB_AUTH_MODE=iam but DB_HOST/DB_USER/DB_NAME/region are not fully set; database features will be unavailable.'
      );
      return;  // Exit early, no database connection
    }

    // Create the appropriate client (static or IAM) and connect
    await this.refreshClient('startup');

    // IAM tokens are short-lived (15 minutes); refresh the client periodically
    // so new connections use fresh tokens before old ones expire
    if (mode === 'iam') {
      // Read refresh interval from config, default to 600 seconds (10 minutes)
      const refreshSeconds = parsePort(this.config.get<string>('DB_IAM_TOKEN_REFRESH_SECONDS'), 600);

      // Disable refresh only if explicitly set to 0 (for testing/debugging)
      if (refreshSeconds > 0) {
        // Set up periodic refresh timer
        this.refreshTimer = setInterval(() => {
          void this.refreshClient('timer');  // Async refresh, don't block timer
        }, refreshSeconds * 1000);
        // Allow process to exit even if timer is active (don't block shutdown)
        this.refreshTimer.unref?.();
      }
    }
  }

  /**
   * NestJS lifecycle hook - called when module is destroyed
   * Cleans up refresh timer and disconnects from database
   */
  async onModuleDestroy(): Promise<void> {
    // Stop IAM token refresh timer if active
    if (this.refreshTimer) clearInterval(this.refreshTimer);
    // Gracefully disconnect from database if connected
    if (this.prisma) await this.prisma.$disconnect();
  }
}
