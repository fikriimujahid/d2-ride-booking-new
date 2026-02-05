// Import NestJS decorators and exceptions
import { Injectable, UnauthorizedException } from '@nestjs/common';
// Import ConfigService to access environment variables
import { ConfigService } from '@nestjs/config';
// Import jose library types for JWT verification
import type { JWTPayload, JWTVerifyGetKey } from 'jose';
// Import system group utilities and types
import { isSystemGroup, type SystemGroup } from './enums/system-group.enum';
// Import Cognito-specific JWT payload interface
import type { CognitoJwtPayload } from './interfaces/cognito-jwt-payload';
// Import authenticated user interface
import type { AuthenticatedUser } from './interfaces/authenticated-user';

/**
 * Type guard to check if value is a non-empty string
 * @param value - Value to check
 * @returns true if value is a string with content after trimming
 */
function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

/**
 * Normalize group name to uppercase for consistent comparison
 * @param value - Raw group name string
 * @returns Uppercased and trimmed group name
 */
function normalizeGroupName(value: string): string {
  return value.trim().toUpperCase();
}

/**
 * Parse and validate Cognito groups from JWT payload
 * Filters to only include recognized SystemGroup values
 * @param payload - Decoded JWT payload
 * @returns Array of valid system groups with duplicates removed
 */
function parseGroups(payload: JWTPayload): readonly SystemGroup[] {
  // Extract cognito:groups claim from JWT
  const raw = payload['cognito:groups'];
  if (!Array.isArray(raw)) return [];

  const groups: SystemGroup[] = [];
  // Iterate through raw group strings
  for (const entry of raw) {
    if (!isNonEmptyString(entry)) continue;  // Skip empty or invalid entries
    const normalized = normalizeGroupName(entry);  // Normalize to uppercase
    if (isSystemGroup(normalized)) groups.push(normalized);  // Only include recognized groups
  }

  // Remove duplicates while preserving order using Set
  return Array.from(new Set(groups));
}

/**
 * Verify that JWT audience or client_id matches expected app client ID
 * Cognito ID tokens use 'aud', access tokens use 'client_id'
 * @param payload - Decoded JWT payload
 * @param expectedClientId - The Cognito app client ID from configuration
 * @returns true if claim matches the expected client ID
 */
function claimMatchesClientId(payload: JWTPayload, expectedClientId: string): boolean {
  // Check 'aud' claim (can be string or array)
  const aud = payload.aud;
  if (typeof aud === 'string' && aud === expectedClientId) return true;
  if (Array.isArray(aud) && aud.some((a) => a === expectedClientId)) return true;

  // Check 'client_id' claim (used by access tokens)
  const clientId = payload['client_id'];
  if (typeof clientId === 'string' && clientId === expectedClientId) return true;

  return false;
}

/**
 * Convert generic JWT payload to typed Cognito payload
 * Validates required claims and throws if invalid
 * @param payload - Raw JWT payload from jose library
 * @returns Typed Cognito JWT payload
 * @throws UnauthorizedException if required claims are missing or invalid
 */
function toCognitoPayload(payload: JWTPayload): CognitoJwtPayload {
  // We only assert strongly required claims we actually use
  // jwtVerify already validated signature, issuer, exp/nbf
  const sub = payload.sub;  // Subject (user ID) - required
  if (!isNonEmptyString(sub)) {
    throw new UnauthorizedException('Unauthorized');
  }

  // Email is optional in Cognito
  const emailRaw = payload.email;
  const email = isNonEmptyString(emailRaw) ? emailRaw : undefined;

  // Groups claim is optional
  const groupsRaw = payload['cognito:groups'];
  const groups = Array.isArray(groupsRaw) && groupsRaw.every((x) => typeof x === 'string') ? (groupsRaw as readonly string[]) : undefined;

  // Extract audience and client_id claims
  const aud = payload.aud;
  const client_id = typeof payload['client_id'] === 'string' ? (payload['client_id'] as string) : undefined;

  // Return typed payload with validated claims
  return {
    ...payload,
    sub,
    email,
    aud,
    client_id,
    'cognito:groups': groups
  };
}

/**
 * CognitoJwtStrategy - Service for verifying AWS Cognito JWT tokens
 * Handles JWT signature verification using Cognito's JWKS endpoint
 * Validates issuer, expiration, audience, and custom claims
 */
@Injectable()
export class CognitoJwtStrategy {
  // Cognito issuer URL for JWT validation
  private readonly issuer: string;
  // Expected Cognito app client ID for audience validation
  private readonly appClientId: string;

  // Lazily initialized JWKS key fetcher (jose is ESM-only, this project is CommonJS)
  private jwks?: JWTVerifyGetKey;
  // Lazily loaded jose module to avoid ESM/CommonJS issues
  private joseModule?: Awaited<typeof import('jose')>;

  /**
   * Constructor - initializes Cognito configuration from environment variables
   * @param config - NestJS ConfigService for reading environment variables
   * @throws Error if required Cognito configuration is missing (fail-fast at startup)
   */
  constructor(private readonly config: ConfigService) {
    // Read Cognito region from environment
    const region = this.config.get<string>('COGNITO_REGION');
    // Read Cognito user pool ID
    const userPoolId = this.config.get<string>('COGNITO_USER_POOL_ID');

    // Read app client ID with fallback to legacy name for backward compatibility
    // New name (required by spec) with backward-compatible fallback
    const appClientId =
      this.config.get<string>('COGNITO_APP_CLIENT_ID') ?? this.config.get<string>('COGNITO_CLIENT_ID');

    // Validate all required configuration is present
    if (!isNonEmptyString(region) || !isNonEmptyString(userPoolId) || !isNonEmptyString(appClientId)) {
      // Fail fast at startup for server misconfiguration (prevents runtime errors)
      throw new Error(
        'Missing Cognito configuration: COGNITO_REGION, COGNITO_USER_POOL_ID, COGNITO_APP_CLIENT_ID'
      );
    }

    this.appClientId = appClientId;
    // Construct the Cognito issuer URL
    this.issuer = `https://cognito-idp.${region}.amazonaws.com/${userPoolId}`;
  }

  /**
   * Lazy-load the jose ESM module
   * @returns Promise resolving to jose module
   */
  private async getJose() {
    if (!this.joseModule) {
      // Dynamic import to load ESM module in CommonJS context
      this.joseModule = await import('jose');
    }
    return this.joseModule;
  }

  /**
   * Get or create JWKS key fetcher for JWT verification
   * Fetches public keys from Cognito's JWKS endpoint
   * @returns Promise resolving to JWKS key getter function
   */
  private async getJwks(): Promise<JWTVerifyGetKey> {
    if (!this.jwks) {
      const jose = await this.getJose();
      // Create remote JWKS fetcher pointing to Cognito's well-known endpoint
      this.jwks = jose.createRemoteJWKSet(new URL(`${this.issuer}/.well-known/jwks.json`));
    }
    return this.jwks;
  }

  /**
   * Verifies a raw JWT string (without "Bearer " prefix)
   * 
   * Security properties enforced:
   * - Cryptographic signature verification via JWKS
   * - Issuer (iss) validation against Cognito URL
   * - Expiration (exp) and not-before (nbf) checks by jose
   * - Audience (aud) OR client_id must match configured app client ID
   * 
   * @param token - Raw JWT token string
   * @returns Promise resolving to authenticated user object
   * @throws UnauthorizedException if token is invalid, expired, or fails verification
   */
  async verifyJwt(token: string): Promise<AuthenticatedUser> {
    try {
      // Load jose module and JWKS fetcher
      const jose = await this.getJose();
      const jwks = await this.getJwks();

      // Verify JWT signature, expiration, and issuer using Cognito's public keys
      const { payload } = await jose.jwtVerify(token, jwks, {
        issuer: this.issuer  // Ensure token was issued by our Cognito user pool
      });

      // Verify audience/client_id matches our app client ID
      if (!claimMatchesClientId(payload, this.appClientId)) {
        throw new UnauthorizedException('Unauthorized');
      }

      // Convert to typed Cognito payload (validates required claims)
      const typedPayload = toCognitoPayload(payload);
      // Extract and validate system groups from claims
      const systemGroups = parseGroups(payload);

      // Return authenticated user object for request context
      return {
        userId: typedPayload.sub,           // Cognito user ID
        email: typedPayload.email ?? '',    // Email (with fallback)
        systemGroups,                        // Parsed system groups
        claims: typedPayload                 // Full verified JWT payload
      };
    } catch (err: unknown) {
      // Re-throw if already UnauthorizedException
      if (err instanceof UnauthorizedException) throw err;

      // Fail closed; do not leak cryptographic/claim details to client
      try {
        const jose = await this.getJose();
        const JoseErrors = jose.errors;

        // Check if error is a known jose JWT error
        if (
          err instanceof JoseErrors.JWTExpired ||           // Token expired
          err instanceof JoseErrors.JWTInvalid ||           // Invalid token format
          err instanceof JoseErrors.JWTClaimValidationFailed ||  // Claim validation failed
          err instanceof JoseErrors.JWSSignatureVerificationFailed ||  // Signature invalid
          err instanceof JoseErrors.JOSEError               // General jose error
        ) {
          throw new UnauthorizedException('Unauthorized');
        }
      } catch {
        // If jose itself fails to load, still fail closed
      }

      // Generic unauthorized error for any unexpected failure (security: don't leak details)
      throw new UnauthorizedException('Unauthorized');
    }
  }
}
