/**
 * Validation checklist (DEV Phase 5)
 * - Backend starts successfully on EC2
 * - /health returns 200
 * - JWT validation works
 * - IAM DB auth token is generated correctly
 * - DB connection succeeds with IAM auth
 * - EC2 is accessible via SSM
 * - ALB can be enabled/disabled safely
 * - API is reachable at api.d2.fikri.dev (when ALB enabled)
 */
import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { ConfigService } from '@nestjs/config';
import { ValidationPipe } from '@nestjs/common';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { JsonLogger } from './logging/json-logger.service';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, {
    bufferLogs: true,
    logger: new JsonLogger('bootstrap')
  });

  const logger = app.get(JsonLogger);
  app.useLogger(logger);
  const config = app.get(ConfigService);

  // Enable global validation for DTOs
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true
    })
  );

  const port = Number(config.get<number>('PORT') ?? 3000);
  const env = config.get<string>('NODE_ENV') ?? 'dev';

  // Swagger API documentation (enabled in dev, disable in production)
  if (env !== 'production') {
    const swaggerConfig = new DocumentBuilder()
      .setTitle('D2 Ride Booking API')
      .setDescription(
        'Backend API for ride-booking demo with AWS Cognito JWT authentication. ' +
          '\n\n**Authentication Flow:**' +
          '\n1. User authenticates via Cognito (frontend handled)' +
          '\n2. Cognito returns JWT access token' +
          '\n3. Frontend sends token in `Authorization: Bearer <token>` header' +
          '\n4. Backend validates JWT signature, issuer, audience, and extracts role claim' +
          '\n5. Endpoints enforce RBAC based on role (ADMIN/DRIVER/PASSENGER)' +
          '\n\n**Getting a Token:**' +
          '\nUse AWS Cognito SDK or Amplify to authenticate. Example with AWS CLI:' +
          '\n```bash' +
          '\naws cognito-idp initiate-auth \\' +
          '\n  --auth-flow USER_PASSWORD_AUTH \\' +
          '\n  --client-id <COGNITO_CLIENT_ID> \\' +
          '\n  --auth-parameters USERNAME=user@example.com,PASSWORD=YourPassword123!' +
          '\n```'
      )
      .setVersion('1.0.0')
      .addBearerAuth(
        {
          type: 'http',
          scheme: 'bearer',
          bearerFormat: 'JWT',
          name: 'Authorization',
          description:
            'Enter JWT token from AWS Cognito. Token must include `sub` (user ID) and optional `custom:role` claim.',
          in: 'header'
        },
        'cognito-jwt'
      )
      .addTag(
        'Auth',
        'Cognito helper endpoints (public). Use these to register/login and retrieve tokens for Swagger testing.'
      )
      .addTag('Health', 'Health check and status endpoints (public, no auth required)')
      .addTag('Profile', 'User profile management (authenticated)')
      .build();

    const document = SwaggerModule.createDocument(app, swaggerConfig);
    SwaggerModule.setup('api/docs', app, document, {
      customSiteTitle: 'D2 Ride Booking API Docs',
      customCss: '.swagger-ui .topbar { display: none }',
      swaggerOptions: {
        persistAuthorization: true,
        docExpansion: 'none',
        filter: true,
        tagsSorter: 'alpha',
        operationsSorter: 'alpha'
      }
    });

    logger.log('Swagger documentation available', { url: `http://localhost:${port}/api/docs` });
  }

  logger.log('backend bootstrapping', { port, env });

  process.on('SIGTERM', () => logger.log('received SIGTERM, shutting down gracefully'));
  process.on('SIGINT', () => logger.log('received SIGINT, shutting down gracefully'));

  await app.listen(port);
  logger.log('backend listening', { port, env });
}

bootstrap().catch((error) => {
  // Explicitly log as JSON so failures are visible in CloudWatch
  // and CI logs without extra tooling.
  console.error(JSON.stringify({ level: 'error', msg: 'bootstrap failed', error: String(error) }));
  process.exit(1);
});
