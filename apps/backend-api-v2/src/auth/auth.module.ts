// Import Global decorator to make this module available across the entire app
// Import Module decorator to define a NestJS module
import { Global, Module } from '@nestjs/common';
// Import Cognito JWT verification strategy
import { CognitoJwtStrategy } from './cognito-jwt.strategy';
// Import JWT authentication guard for protecting routes
import { JwtAuthGuard } from './jwt-auth.guard';
// Import system group authorization guard
import { SystemGroupGuard } from './system-group.guard';

/**
 * AuthModule - Global authentication module
 * Provides JWT verification using AWS Cognito and system-level authorization
 * Marked as @Global so guards and strategies are available throughout the app
 */
@Global()
@Module({
  // Register authentication-related providers
  providers: [CognitoJwtStrategy, JwtAuthGuard, SystemGroupGuard],
  // Export providers to be injectable in other modules without re-importing AuthModule
  exports: [CognitoJwtStrategy, JwtAuthGuard, SystemGroupGuard]
})
export class AuthModule {}
