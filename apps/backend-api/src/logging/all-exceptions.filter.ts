import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { JsonLogger } from './json-logger.service';

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  constructor(private readonly logger: JsonLogger) {}

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const req = ctx.getRequest<Request & { requestId?: string; user?: { sub?: string; role?: string } }>();
    const res = ctx.getResponse<Response>();

    const isHttp = exception instanceof HttpException;
    const statusCode = isHttp ? exception.getStatus() : HttpStatus.INTERNAL_SERVER_ERROR;

    const path = req.originalUrl?.split('?')[0] ?? req.url;

    const meta: Record<string, unknown> = {
      requestId: req.requestId,
      method: req.method,
      path,
      statusCode
    };

    if (req.user?.sub) meta.userSub = req.user.sub;
    if (req.user?.role) meta.userRole = req.user.role;

    if (exception instanceof Error) {
      meta.errorName = exception.name;
      meta.errorMessage = exception.message;
      meta.stack = exception.stack;
    } else {
      meta.error = String(exception);
    }

    // Log 5xx as error (with stack), 4xx as warn.
    if (statusCode >= 500) {
      this.logger.error('Unhandled exception', meta);
    } else {
      this.logger.warn('Request failed', meta);
    }

    // Return consistent JSON errors without leaking stack traces to clients.
    // (Stack is in logs; clients get a stable message.)
    const body = isHttp
      ? exception.getResponse()
      : {
          statusCode,
          message: 'Internal server error'
        };

    res.status(statusCode).json(body);
  }
}
