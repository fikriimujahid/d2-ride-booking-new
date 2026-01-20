import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ConfigModule } from '@nestjs/config';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { DatabaseService } from './database/database.service';
import { JsonLogger } from './logging/json-logger.service';
import { JwtAuthGuard } from './auth/jwt-auth.guard';
import { JwtVerifierService } from './auth/jwt-verifier.service';
import { CognitoAuthController } from './auth/cognito-auth.controller';
import { CognitoAuthService } from './auth/cognito-auth.service';
import { validateEnv } from './config/env.validation';
import { ProfileModule } from './profile/profile.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      // Rely on environment variables provided by EC2 user-data/SSM for runtime.
      // .env files are optional for local development only.
      envFilePath: ['.env', '.env.local'],
      validate: validateEnv
    }),
    ProfileModule
  ],
  controllers: [AppController, CognitoAuthController],
  providers: [
    AppService,
    DatabaseService,
    JsonLogger,
    JwtVerifierService,
    CognitoAuthService,
    {
      // Enforce JWT verification across the API; mark endpoints with @Public to skip.
      provide: APP_GUARD,
      useClass: JwtAuthGuard
    }
  ]
})
export class AppModule {}
