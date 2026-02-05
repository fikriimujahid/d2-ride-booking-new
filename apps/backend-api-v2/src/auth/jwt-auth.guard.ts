// Import NestJS guards and exceptions for route protection
import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
// Import Express Request type for type safety
import type { Request } from 'express';
// Import Cognito JWT verification strategy
import { CognitoJwtStrategy } from './cognito-jwt.strategy';

/**
 * Extract and validate Bearer token from Authorization header
 * @param req - Express request object
 * @returns The extracted JWT token without the "Bearer " prefix
 * @throws UnauthorizedException if token is missing or malformed
 */
function extractBearerToken(req: Request): string {
  // Get the Authorization header (case-insensitive)
  const header = req.header('authorization');
  if (!header) throw new UnauthorizedException('Unauthorized');

  // Split "Bearer <token>" into scheme and value
  const [scheme, value] = header.split(' ');
  if (!scheme || !value) throw new UnauthorizedException('Unauthorized');
  // Verify the scheme is "Bearer" (case-insensitive)
  if (scheme.toLowerCase() !== 'bearer') throw new UnauthorizedException('Unauthorized');

  // Extract and validate the token part
  const token = value.trim();
  if (token.length === 0) throw new UnauthorizedException('Unauthorized');
  return token;
}

/**
 * JwtAuthGuard - NestJS guard for JWT authentication
 * Verifies JWT tokens from AWS Cognito and attaches authenticated user to request
 * Use with @UseGuards(JwtAuthGuard) on controllers or routes
 */
@Injectable()
export class JwtAuthGuard implements CanActivate {
  // Inject the Cognito JWT verification strategy
  constructor(private readonly strategy: CognitoJwtStrategy) {}

  /**
   * Guard activation method - called before route handler
   * @param context - Execution context containing request information
   * @returns true if authentication succeeds, throws UnauthorizedException otherwise
   */
  async canActivate(context: ExecutionContext): Promise<boolean> {
    // Get the HTTP request object from the execution context
    const request = context.switchToHttp().getRequest<Request>();
    // Extract the JWT token from the Authorization header
    const token = extractBearerToken(request);

    // Verify the JWT token using Cognito strategy (validates signature, expiration, issuer)
    const user = await this.strategy.verifyJwt(token);
    // Attach the authenticated user object to the request for downstream use
    request.user = user;
    // Allow the request to proceed to the route handler
    return true;
  }
}
