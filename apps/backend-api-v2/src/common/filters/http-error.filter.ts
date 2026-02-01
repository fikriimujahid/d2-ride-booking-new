import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { ERROR_CODES } from '../http/error-codes';
import type { ErrorResponseBody } from '../http/error-response';

function safeMessageForStatus(statusCode: number): string {
  if (statusCode === HttpStatus.UNAUTHORIZED) return 'Unauthorized';
  if (statusCode === HttpStatus.FORBIDDEN) return 'Forbidden';
  return 'Internal Server Error';
}

function errorCodeForStatus(statusCode: number): ErrorResponseBody['errorCode'] {
  if (statusCode === HttpStatus.UNAUTHORIZED) return ERROR_CODES.UNAUTHENTICATED;
  if (statusCode === HttpStatus.FORBIDDEN) return ERROR_CODES.FORBIDDEN;
  return ERROR_CODES.INTERNAL;
}

@Catch()
export class HttpErrorFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    const statusCode = exception instanceof HttpException ? exception.getStatus() : HttpStatus.INTERNAL_SERVER_ERROR;

    const body: ErrorResponseBody = {
      statusCode,
      errorCode: errorCodeForStatus(statusCode),
      // Never echo framework/AWS/JWT details.
      message: safeMessageForStatus(statusCode),
      timestamp: new Date().toISOString(),
      path: request.originalUrl ?? request.url,
      requestId: request.requestId
    };

    response.status(statusCode).json(body);
  }
}
