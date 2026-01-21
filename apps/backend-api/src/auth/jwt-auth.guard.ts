import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Request } from 'express';
import { JwtVerifierService } from './jwt-verifier.service';
import { JsonLogger } from '../logging/json-logger.service';

// Guard validates Cognito JWTs and attaches role claim for future RBAC.
// Flow summary: Frontend obtains JWT from Cognito after login -> sends it in
// Authorization: Bearer <token> -> guard verifies signature/issuer/clientId
// using Cognito JWKs -> role claim (ADMIN/DRIVER/PASSENGER) is attached to
// request.user -> later, route-level decorators can enforce RBAC based on role.
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly verifier: JwtVerifierService,
    private readonly logger: JsonLogger
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.get<boolean>('isPublic', context.getHandler());
    if (isPublic) {
      return true;
    }

    const request = context.switchToHttp().getRequest<Request & { user?: unknown }>();
    const token = this.extractToken(request);
    if (!token) {
      this.logger.warn('Missing JWT');
      throw new UnauthorizedException('Authorization header missing or malformed');
    }

    try {
      const payload = await this.verifier.verify(token);
      request.user = payload;
      this.logger.log('JWT verified', { role: payload.role });
      return true;
    } catch (error) {
      this.logger.error('JWT validation failed', { error: (error as Error).message });
      throw new UnauthorizedException('Invalid or expired token');
    }
  }

  private extractToken(request: Request): string | undefined {
    const authHeader = request.headers['authorization'];
    if (!authHeader) return undefined;
    const [scheme, token] = authHeader.split(' ');
    return scheme === 'Bearer' && token ? token : undefined;
  }
}
