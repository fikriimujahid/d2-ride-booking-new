// Import reflect-metadata to enable TypeScript decorators and metadata reflection
// This is required for NestJS dependency injection and decorator functionality
import 'reflect-metadata';
// Import NestFactory to bootstrap the NestJS application
import { NestFactory } from '@nestjs/core';
// Import ValidationPipe for automatic DTO validation
import { ValidationPipe } from '@nestjs/common';
// Import Swagger utilities for API documentation generation
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
// Import the root application module
import { AppModule } from './app.module';
// Import custom error filter to standardize HTTP error responses
import { HttpErrorFilter } from './common/filters/http-error.filter';
// Import middleware to attach unique request IDs for tracing and logging
import { requestIdMiddleware } from './common/request/request-id.middleware';

/**
 * Bootstrap function - Entry point for the NestJS application
 * Initializes the app, configures middleware, validation, error handling, and Swagger docs
 */
async function bootstrap() {
  // Create a NestJS application instance using the root AppModule
  // bufferLogs: true queues logs until a logger is attached, preventing loss during startup
  const app = await NestFactory.create(AppModule, {
    bufferLogs: true
  });

  // Configure global validation pipe for all incoming requests
  // DTO validation defaults (safe-by-default approach for security)
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,            // Strip properties that don't have decorators in the DTO
      forbidNonWhitelisted: true, // Throw error if unknown properties are present
      transform: true             // Automatically transform payloads to DTO instances
    })
  );

  // Apply request ID middleware globally to all routes
  // Correlation ID middleware - adds a unique ID to each request for distributed tracing
  app.use(requestIdMiddleware);

  // Register global exception filter to ensure consistent error response format
  // Auth-safe error shape - prevents leaking sensitive information in error messages
  app.useGlobalFilters(new HttpErrorFilter());

  // Read Swagger configuration from environment variable
  const swaggerEnabledRaw = process.env.SWAGGER_ENABLED;
  // Enable Swagger by default unless explicitly set to 'false' (case-insensitive)
  const swaggerEnabled = swaggerEnabledRaw ? swaggerEnabledRaw.trim().toLowerCase() !== 'false' : true;
  
  // Conditionally set up Swagger/OpenAPI documentation
  if (swaggerEnabled) {
    // Build Swagger configuration with API metadata
    const config = new DocumentBuilder()
      .setTitle('D2 Ride Booking API (v2)')  // API title displayed in Swagger UI
      .setDescription('AuthN (Cognito) + System Groups + Admin RBAC')  // API description
      .setVersion('1.0.0')  // API version
      // Configure Bearer token authentication for Swagger UI
      .addBearerAuth(
        {
          type: 'http',           // HTTP authentication type
          scheme: 'bearer',       // Bearer token scheme
          bearerFormat: 'JWT',    // JWT token format
          name: 'Authorization',  // Header name
          in: 'header'            // Token location (header)
        },
        'bearer'  // Security scheme identifier used in @ApiBearerAuth() decorators
      )
      .build();

    // Generate OpenAPI document from NestJS controllers and decorators
    const document = SwaggerModule.createDocument(app, config);
    // Apply bearer authentication globally to all endpoints by default
    document.security = [{ bearer: [] }];
    // Setup Swagger UI at /docs endpoint
    SwaggerModule.setup('docs', app, document, {
      swaggerOptions: { persistAuthorization: true }  // Remember auth token across page refreshes
    });
  }

  // Read port from environment variable or default to 3000
  const portRaw = process.env.PORT;
  const port = portRaw ? Number(portRaw) : 3000;

  // Start the HTTP server and listen for incoming requests
  // Use the configured port if it's a valid number, otherwise fall back to 3000
  await app.listen(Number.isFinite(port) ? port : 3000);
}

// Execute the bootstrap function to start the application
bootstrap();
