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
import { createHttpLoggingMiddleware } from './logging/http-logging.middleware';
import { AllExceptionsFilter } from './logging/all-exceptions.filter';

async function bootstrap() {
  // Dev-only workaround for environments that intercept HTTPS with a custom/self-signed CA.
  // Prefer setting NODE_EXTRA_CA_CERTS to your corporate root CA instead.
  const allowSelfSignedRaw = (process.env.ALLOW_SELF_SIGNED_CERTS ?? '').toLowerCase();
  const allowSelfSigned = allowSelfSignedRaw === 'true' || allowSelfSignedRaw === '1' || allowSelfSignedRaw === 'yes';
  const nodeEnv = process.env.NODE_ENV ?? 'dev';
  if (allowSelfSigned && nodeEnv !== 'production') {
    process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
    console.warn(
      JSON.stringify({
        level: 'warn',
        msg: 'ALLOW_SELF_SIGNED_CERTS enabled: TLS certificate verification is disabled (dev only)',
        hint: 'Prefer using NODE_EXTRA_CA_CERTS with your corporate CA when possible.'
      })
    );
  }

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

  // Dev-friendly log levels.
  // In production, keep noise down; in dev, enable verbose debugging.
  logger.setLogLevels(env === 'production' ? ['log', 'warn', 'error'] : ['log', 'warn', 'error', 'debug', 'verbose']);

  // Request/response logs (no headers/body; safe for dev + prod).
  app.use(createHttpLoggingMiddleware(logger));

  // Ensure 5xx errors always include stack traces in logs.
  app.useGlobalFilters(new AllExceptionsFilter(logger));

  // CORS
  // - Local dev: allow Vite dev server(s) to call the API with Bearer tokens.
  // - Prod: enable only when explicitly configured (or when same-origin is used).
  const corsOriginsRaw = config.get<string>('CORS_ORIGINS');
  const corsOrigins = (corsOriginsRaw ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

  const devDefaultOrigins = [
    'http://localhost:5173',
    'http://127.0.0.1:5173',
    'http://localhost:3000',
    'http://127.0.0.1:3000',
    'http://localhost:3001',
    'http://127.0.0.1:3001',
    'http://localhost:4173',
    'http://127.0.0.1:4173',
    'https://fikri.dev',
    'https://admin.d2.fikri.dev',
    'https://driver.d2.fikri.dev',
    'https://api.d2.fikri.dev',
    'https://passenger.d2.fikri.dev'
  ];

  const prodDefaultOrigins = [
    'https://admin.d2.fikri.dev',
    'https://driver.d2.fikri.dev',
    'https://api.d2.fikri.dev',
    'https://passenger.d2.fikri.dev'
  ];

  // In production, we still need explicit CORS for the public web apps hosted on
  // different subdomains (e.g., admin -> api). For dev ergonomics, configured
  // CORS_ORIGINS is treated as additive (merged with defaults).
  const defaultOrigins = env === 'production' ? prodDefaultOrigins : devDefaultOrigins;
  // Best practice for dev ergonomics: treat configured origins as additive.
  // This avoids accidentally blocking same-origin tools (e.g., Swagger at api.*)
  // when CORS_ORIGINS is set by Terraform.
  const allowList = Array.from(
    new Set([...(defaultOrigins ?? []), ...(corsOrigins.length > 0 ? corsOrigins : [])])
  );

  const normalizeOrigin = (value: string) => value.trim().replace(/\/$/, '');
  const allowSet = new Set(allowList.map(normalizeOrigin));

  if (allowList.length > 0) {

    app.enableCors({
      origin: (
        origin: string | undefined,
        callback: (err: Error | null, allow?: boolean) => void
      ) => {
        // Allow non-browser clients (curl/Postman) which have no Origin header.
        if (!origin) return callback(null, true);
        const normalized = normalizeOrigin(origin);
        if (allowSet.has(normalized)) return callback(null, true);
        logger.warn('CORS blocked origin', {
          origin,
          normalized,
          allowListCount: allowList.length,
          allowListSample: allowList.slice(0, 10)
        });
        return callback(new Error(`CORS blocked origin: ${origin}`), false);
      },
      // If frontends ever use cookies, this must be true.
      // Safe with an allowlist (never use credentials with '*').
      credentials: true,
      methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
      // Leave allowedHeaders undefined so the CORS middleware echoes
      // the browser's Access-Control-Request-Headers on preflight.
      optionsSuccessStatus: 204,
      maxAge: 86400
    });

    logger.log('CORS enabled', { allowList });
  }

  // Swagger API documentation (enabled in dev, disable in production)
  if (env !== 'productions') {
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

  process.on('unhandledRejection', (reason) => {
    logger.error('unhandledRejection', { reason: reason instanceof Error ? reason.stack ?? reason.message : String(reason) });
  });

  process.on('uncaughtException', (error) => {
    logger.error('uncaughtException', { error: error.stack ?? error.message });
  });

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
