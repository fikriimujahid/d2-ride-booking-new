import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createRemoteJWKSet, jwtVerify, JWTPayload } from 'jose';
import { JsonLogger } from '../logging/json-logger.service';

/**
 * JWT verification using Cognito JWKs.
 * - Validates signature, issuer, and clientId
 * - Extracts role claim (custom:role | cognito:groups | role)
 */
@Injectable()
export class JwtVerifierService {
  private jwks?: ReturnType<typeof createRemoteJWKSet>;
  private issuer: string;
  private clientId: string;

  constructor(private readonly config: ConfigService, private readonly logger: JsonLogger) {
    const region = this.config.get<string>('AWS_REGION');
    const userPoolId = this.config.get<string>('COGNITO_USER_POOL_ID');
    this.issuer = `https://cognito-idp.${region}.amazonaws.com/${userPoolId}`;
    this.clientId = this.config.get<string>('COGNITO_CLIENT_ID') ?? '';
  }

  private getJwks(): ReturnType<typeof createRemoteJWKSet> {
    if (!this.jwks) {
      const jwksUri = `${this.issuer}/.well-known/jwks.json`;
      this.jwks = createRemoteJWKSet(new URL(jwksUri));
      this.logger.log('JWKS remote set initialized', { jwksUri });
    }
    return this.jwks;
  }

  async verify(token: string): Promise<JWTPayload & { role?: string }> {
    const { payload } = await jwtVerify(token, this.getJwks(), {
      issuer: this.issuer
    });

    this.assertClientId(payload);

    const role = (payload['custom:role'] as string) || this.extractGroup(payload) || (payload['role'] as string);
    return { ...payload, role };
  }

  private assertClientId(payload: JWTPayload) {
    // Cognito ID tokens typically use `aud` for the app client id.
    // Cognito access tokens often use `client_id` instead.
    const aud = payload.aud;
    const audMatches = Array.isArray(aud) ? aud.includes(this.clientId) : aud === this.clientId;
    const clientIdClaim = payload['client_id'] as string | undefined;

    if (!this.clientId) {
      // If config validation is relaxed, fail closed here.
      throw new Error('COGNITO_CLIENT_ID is not configured');
    }

    if (!audMatches && clientIdClaim !== this.clientId) {
      throw new Error('JWT client id (aud/client_id) does not match configured COGNITO_CLIENT_ID');
    }
  }

  private extractGroup(payload: JWTPayload): string | undefined {
    const groups = payload['cognito:groups'];
    if (Array.isArray(groups) && groups.length > 0) {
      return String(groups[0]);
    }
    return undefined;
  }
}
