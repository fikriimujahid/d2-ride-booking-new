import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { HttpErrorFilter } from './common/filters/http-error.filter';
import { requestIdMiddleware } from './common/request/request-id.middleware';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, {
    bufferLogs: true
  });

  // DTO validation defaults (safe-by-default).
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true
    })
  );

  // Correlation ID middleware.
  app.use(requestIdMiddleware);

  // Auth-safe error shape.
  app.useGlobalFilters(new HttpErrorFilter());

  const swaggerEnabledRaw = process.env.SWAGGER_ENABLED;
  const swaggerEnabled = swaggerEnabledRaw ? swaggerEnabledRaw.trim().toLowerCase() !== 'false' : true;
  if (swaggerEnabled) {
    const config = new DocumentBuilder()
      .setTitle('D2 Ride Booking API (v2)')
      .setDescription('AuthN (Cognito) + System Groups + Admin RBAC')
      .setVersion('1.0.0')
      .addBearerAuth(
        {
          type: 'http',
          scheme: 'bearer',
          bearerFormat: 'JWT',
          name: 'Authorization',
          in: 'header'
        },
        'bearer'
      )
      .build();

    const document = SwaggerModule.createDocument(app, config);
    document.security = [{ bearer: [] }];
    SwaggerModule.setup('docs', app, document, {
      swaggerOptions: { persistAuthorization: true }
    });
  }

  const portRaw = process.env.PORT;
  const port = portRaw ? Number(portRaw) : 3000;

  await app.listen(Number.isFinite(port) ? port : 3000);
}

bootstrap();
