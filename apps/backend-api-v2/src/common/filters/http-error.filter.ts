// Import NestJS exception handling utilities
import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus
} from '@nestjs/common';
// Import Express types for request/response
import type { Request, Response } from 'express';
// Import standardized error codes
import { ERROR_CODES } from '../http/error-codes';
// Import error response body interface
import type { ErrorResponseBody } from '../http/error-response';

/**
 * Get a safe, generic error message for a given HTTP status code
 * Prevents leaking sensitive information in error responses
 * @param statusCode - HTTP status code
 * @returns Generic error message string
 */
function safeMessageForStatus(statusCode: number): string {
  if (statusCode === HttpStatus.UNAUTHORIZED) return 'Unauthorized';
  if (statusCode === HttpStatus.FORBIDDEN) return 'Forbidden';
  // Default to generic internal error message for all other status codes
  return 'Internal Server Error';
}

/**
 * Map HTTP status code to application-specific error code
 * @param statusCode - HTTP status code
 * @returns Application error code constant
 */
function errorCodeForStatus(statusCode: number): ErrorResponseBody['errorCode'] {
  if (statusCode === HttpStatus.UNAUTHORIZED) return ERROR_CODES.UNAUTHENTICATED;
  if (statusCode === HttpStatus.FORBIDDEN) return ERROR_CODES.FORBIDDEN;
  // Default to internal error code
  return ERROR_CODES.INTERNAL;
}

/**
 * HttpErrorFilter - Global exception filter for consistent error responses
 * Catches all exceptions and formats them into a standardized error response
 * Prevents leaking sensitive framework, AWS, or JWT details to clients
 * @Catch() with no arguments catches all exception types
 */
@Catch()
export class HttpErrorFilter implements ExceptionFilter {
  /**
   * Exception handler method - called when any exception occurs
   * @param exception - The caught exception (can be any type)
   * @param host - ArgumentsHost providing access to request/response
   */
  catch(exception: unknown, host: ArgumentsHost): void {
    // Switch to HTTP context to access Express request/response
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    // Extract status code from HttpException, default to 500 for unknown errors
    const statusCode = exception instanceof HttpException ? exception.getStatus() : HttpStatus.INTERNAL_SERVER_ERROR;

    // Build standardized error response body
    const body: ErrorResponseBody = {
      statusCode,                               // HTTP status code
      errorCode: errorCodeForStatus(statusCode), // Application error code
      // Use generic message - never echo framework/AWS/JWT details (security)
      message: safeMessageForStatus(statusCode),
      timestamp: new Date().toISOString(),      // ISO timestamp for debugging
      path: request.originalUrl ?? request.url,  // Request path that caused error
      requestId: request.requestId               // Correlation ID for tracing
    };

    // Send JSON error response with appropriate status code
    response.status(statusCode).json(body);
  }
}
