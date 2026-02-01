import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
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

  const portRaw = process.env.PORT;
  const port = portRaw ? Number(portRaw) : 3000;

  await app.listen(Number.isFinite(port) ? port : 3000);
}

bootstrap();
