import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { validateEnv } from './config/env.validation';
import { AuthModule } from './auth/auth.module';
import { HealthModule } from './health/health.module';
import { PrismaModule } from './database/prisma.module';
import { AuditModule } from './audit/audit.module';
import { IamModule } from './iam/iam.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: ['.env', '.env.local'],
      validate: validateEnv
    }),
    AuthModule,
    PrismaModule,
    AuditModule,
    IamModule,
    HealthModule
  ]
})
export class AppModule {}
