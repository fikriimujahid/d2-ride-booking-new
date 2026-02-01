import { Global, Module } from '@nestjs/common';
import { CognitoJwtStrategy } from './cognito-jwt.strategy';
import { JwtAuthGuard } from './jwt-auth.guard';
import { SystemGroupGuard } from './system-group.guard';

@Global()
@Module({
  providers: [CognitoJwtStrategy, JwtAuthGuard, SystemGroupGuard],
  exports: [CognitoJwtStrategy, JwtAuthGuard, SystemGroupGuard]
})
export class AuthModule {}
