import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import type { Request } from 'express';
import { CognitoJwtStrategy } from './cognito-jwt.strategy';

function extractBearerToken(req: Request): string {
  const header = req.header('authorization');
  if (!header) throw new UnauthorizedException('Unauthorized');

  const [scheme, value] = header.split(' ');
  if (!scheme || !value) throw new UnauthorizedException('Unauthorized');
  if (scheme.toLowerCase() !== 'bearer') throw new UnauthorizedException('Unauthorized');

  const token = value.trim();
  if (token.length === 0) throw new UnauthorizedException('Unauthorized');
  return token;
}

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly strategy: CognitoJwtStrategy) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<Request>();
    const token = extractBearerToken(request);

    const user = await this.strategy.verifyJwt(token);
    request.user = user;
    return true;
  }
}
