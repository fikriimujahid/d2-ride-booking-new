// Import NestJS Module decorator to define the root module
import { Module } from '@nestjs/common';
// Import ConfigModule to manage environment variables and configuration
import { ConfigModule } from '@nestjs/config';
// Import environment variable validation function
import { validateEnv } from './config/env.validation';
// Import authentication module for JWT/Cognito integration
import { AuthModule } from './auth/auth.module';
// Import health check module for monitoring application status
import { HealthModule } from './health/health.module';
// Import Prisma database module for ORM functionality
import { PrismaModule } from './database/prisma.module';
// Import audit module for tracking user actions and changes
import { AuditModule } from './audit/audit.module';
// Import IAM module for Identity and Access Management (RBAC)
import { IamModule } from './iam/iam.module';

/**
 * AppModule - Root module of the application
 * Orchestrates all feature modules and provides global configuration
 */
@Module({
  imports: [
    // Configure environment variable loading and validation
    ConfigModule.forRoot({
      isGlobal: true,  // Make ConfigService available globally without re-importing
      envFilePath: ['.env', '.env.local'],  // Load from .env files (local overrides default)
      validate: validateEnv  // Validate required environment variables on startup
    }),
    // Authentication and authorization module (JWT verification, Cognito integration)
    AuthModule,
    // Database module providing Prisma ORM service
    PrismaModule,
    // Audit logging module for compliance and tracking
    AuditModule,
    // Identity and Access Management module (roles, permissions, RBAC)
    IamModule,
    // Health check endpoints for load balancers and monitoring
    HealthModule
  ]
})
export class AppModule {}
