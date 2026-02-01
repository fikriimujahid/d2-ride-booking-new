import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { JWTPayload, JWTVerifyGetKey } from 'jose';
import { isSystemGroup, type SystemGroup } from './enums/system-group.enum';
import type { CognitoJwtPayload } from './interfaces/cognito-jwt-payload';
import type { AuthenticatedUser } from './interfaces/authenticated-user';

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function normalizeGroupName(value: string): string {
  return value.trim().toUpperCase();
}

function parseGroups(payload: JWTPayload): readonly SystemGroup[] {
  const raw = payload['cognito:groups'];
  if (!Array.isArray(raw)) return [];

  const groups: SystemGroup[] = [];
  for (const entry of raw) {
    if (!isNonEmptyString(entry)) continue;
    const normalized = normalizeGroupName(entry);
    if (isSystemGroup(normalized)) groups.push(normalized);
  }

  // Remove duplicates while preserving order.
  return Array.from(new Set(groups));
}

function claimMatchesClientId(payload: JWTPayload, expectedClientId: string): boolean {
  const aud = payload.aud;
  if (typeof aud === 'string' && aud === expectedClientId) return true;
  if (Array.isArray(aud) && aud.some((a) => a === expectedClientId)) return true;

  const clientId = payload['client_id'];
  if (typeof clientId === 'string' && clientId === expectedClientId) return true;

  return false;
}

function toCognitoPayload(payload: JWTPayload): CognitoJwtPayload {
  // We only assert strongly required claims we actually use.
  // `jwtVerify` already validated signature, issuer, exp/nbf.
  const sub = payload.sub;
  if (!isNonEmptyString(sub)) {
    throw new UnauthorizedException('Unauthorized');
  }

  const emailRaw = payload.email;
  const email = isNonEmptyString(emailRaw) ? emailRaw : undefined;

  const groupsRaw = payload['cognito:groups'];
  const groups = Array.isArray(groupsRaw) && groupsRaw.every((x) => typeof x === 'string') ? (groupsRaw as readonly string[]) : undefined;

  const aud = payload.aud;
  const client_id = typeof payload['client_id'] === 'string' ? (payload['client_id'] as string) : undefined;

  return {
    ...payload,
    sub,
    email,
    aud,
    client_id,
    'cognito:groups': groups
  };
}

@Injectable()
export class CognitoJwtStrategy {
  private readonly issuer: string;
  private readonly appClientId: string;

  // Lazily initialized because `jose` is ESM-only and this project compiles to CommonJS.
  private jwks?: JWTVerifyGetKey;
  private joseModule?: Awaited<typeof import('jose')>;

  constructor(private readonly config: ConfigService) {
    const region = this.config.get<string>('COGNITO_REGION');
    const userPoolId = this.config.get<string>('COGNITO_USER_POOL_ID');

    // New name (required by spec) with backward-compatible fallback.
    const appClientId =
      this.config.get<string>('COGNITO_APP_CLIENT_ID') ?? this.config.get<string>('COGNITO_CLIENT_ID');

    if (!isNonEmptyString(region) || !isNonEmptyString(userPoolId) || !isNonEmptyString(appClientId)) {
      // Fail fast at startup for server misconfiguration.
      throw new Error(
        'Missing Cognito configuration: COGNITO_REGION, COGNITO_USER_POOL_ID, COGNITO_APP_CLIENT_ID'
      );
    }

    this.appClientId = appClientId;
    this.issuer = `https://cognito-idp.${region}.amazonaws.com/${userPoolId}`;
  }

  private async getJose() {
    if (!this.joseModule) {
      this.joseModule = await import('jose');
    }
    return this.joseModule;
  }

  private async getJwks(): Promise<JWTVerifyGetKey> {
    if (!this.jwks) {
      const jose = await this.getJose();
      this.jwks = jose.createRemoteJWKSet(new URL(`${this.issuer}/.well-known/jwks.json`));
    }
    return this.jwks;
  }

  /**
   * Verifies a raw JWT string (no "Bearer ").
   *
   * Security properties:
   * - Signature via JWKS
   * - `iss` validation
   * - `exp`/`nbf` enforced by jose
   * - `aud` OR `client_id` must match configured app client id
   */
  async verifyJwt(token: string): Promise<AuthenticatedUser> {
    try {
      const jose = await this.getJose();
      const jwks = await this.getJwks();

      const { payload } = await jose.jwtVerify(token, jwks, {
        issuer: this.issuer
      });

      if (!claimMatchesClientId(payload, this.appClientId)) {
        throw new UnauthorizedException('Unauthorized');
      }

      const typedPayload = toCognitoPayload(payload);
      const systemGroups = parseGroups(payload);

      return {
        userId: typedPayload.sub,
        email: typedPayload.email ?? '',
        systemGroups,
        claims: typedPayload
      };
    } catch (err: unknown) {
      if (err instanceof UnauthorizedException) throw err;

      // Fail closed; do not leak cryptographic/claim details.
      try {
        const jose = await this.getJose();
        const JoseErrors = jose.errors;

        if (
          err instanceof JoseErrors.JWTExpired ||
          err instanceof JoseErrors.JWTInvalid ||
          err instanceof JoseErrors.JWTClaimValidationFailed ||
          err instanceof JoseErrors.JWSSignatureVerificationFailed ||
          err instanceof JoseErrors.JOSEError
        ) {
          throw new UnauthorizedException('Unauthorized');
        }
      } catch {
        // If jose itself fails to load, still fail closed.
      }

      throw new UnauthorizedException('Unauthorized');
    }
  }
}
