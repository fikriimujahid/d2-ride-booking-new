// Import Express middleware types
import type { NextFunction, Request, Response } from 'express';
// Import Node.js crypto module for UUID generation
import { randomUUID } from 'node:crypto';

/**
 * Request ID middleware - Assigns a unique identifier to each HTTP request
 * Enables distributed tracing across services and log correlation
 * 
 * Behavior:
 * - If client sends 'x-request-id' header, use that value (for cross-service tracing)
 * - Otherwise, generate a new UUID v4
 * - Attaches request ID to req.requestId for use in logging and error responses
 * - Echoes request ID back to client via 'x-request-id' response header
 * 
 * @param req - Express request object
 * @param res - Express response object
 * @param next - Express next function to continue middleware chain
 */
export function requestIdMiddleware(req: Request, res: Response, next: NextFunction): void {
  // Try to read existing request ID from client's x-request-id header
  const incoming = req.header('x-request-id');
  // Use incoming ID if valid (non-empty after trimming), otherwise generate new UUID
  const requestId = (incoming && incoming.trim().length > 0 ? incoming.trim() : randomUUID());
  // Attach request ID to request object for access in handlers and filters
  req.requestId = requestId;
  // Set response header so client receives the request ID for debugging
  res.setHeader('x-request-id', requestId);
  // Continue to next middleware or route handler
  next();
}
