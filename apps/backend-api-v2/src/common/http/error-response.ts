// Import ErrorCode type from error codes constants
import type { ErrorCode } from './error-codes';

/**
 * ErrorResponseBody interface - Standardized structure for all HTTP error responses
 * Ensures consistent error format across the entire API
 * Used by HttpErrorFilter to format exception responses
 */
export interface ErrorResponseBody {
  /** HTTP status code (e.g., 400, 401, 403, 500) */
  statusCode: number;
  
  /** Application-specific error code for client-side error handling */
  errorCode: ErrorCode;
  
  /** Human-readable error message (generic to avoid leaking sensitive info) */
  message: string;
  
  /** ISO 8601 timestamp when the error occurred */
  timestamp: string;
  
  /** Request path that triggered the error */
  path: string;
  
  /** Unique request ID for distributed tracing and debugging (optional) */
  requestId?: string;
}
