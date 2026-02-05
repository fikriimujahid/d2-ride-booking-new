/**
 * ERROR_CODES - Constant object defining application-specific error codes
 * These codes provide machine-readable error identifiers for API clients
 * Allows frontend applications to handle errors programmatically
 * Using 'as const' makes the object readonly and enables precise type inference
 */
export const ERROR_CODES = {
  /** User is not authenticated (missing or invalid JWT token) */
  UNAUTHENTICATED: 'UNAUTHENTICATED',
  
  /** User is authenticated but lacks required permissions */
  FORBIDDEN: 'FORBIDDEN',
  
  /** Internal server error or unexpected exception */
  INTERNAL: 'INTERNAL'
} as const;

/**
 * ErrorCode type - Union type of all possible error code values
 * Extracted from ERROR_CODES object using TypeScript mapped types
 * Example: 'UNAUTHENTICATED' | 'FORBIDDEN' | 'INTERNAL'
 */
export type ErrorCode = (typeof ERROR_CODES)[keyof typeof ERROR_CODES];
