import type { ErrorCode } from './error-codes';

export interface ErrorResponseBody {
  statusCode: number;
  errorCode: ErrorCode;
  message: string;
  timestamp: string;
  path: string;
  requestId?: string;
}
