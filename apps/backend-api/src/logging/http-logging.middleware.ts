import type { NextFunction, Request, Response } from 'express';
import { JsonLogger } from './json-logger.service';

type AuthedUser = {
  sub?: string;
  role?: string;
};

declare module 'express-serve-static-core' {
  interface Request {
    requestId?: string;
    user?: AuthedUser;
  }
}

function safePath(req: Request): string {
  // Avoid logging query strings with secrets. Keep just the path.
  return req.originalUrl?.split('?')[0] ?? req.url ?? '';
}

function generateRequestId(): string {
  // Keep it simple, no extra deps.
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

export function createHttpLoggingMiddleware(logger: JsonLogger) {
  return function httpLoggingMiddleware(req: Request, res: Response, next: NextFunction) {
    const start = process.hrtime.bigint();

    const incomingId = req.header('x-request-id');
    const requestId = incomingId && incomingId.trim().length > 0 ? incomingId.trim() : generateRequestId();
    req.requestId = requestId;
    res.setHeader('x-request-id', requestId);

    res.on('finish', () => {
      const durationMs = Number(process.hrtime.bigint() - start) / 1_000_000;

      const user = (req as Request & { user?: AuthedUser }).user;
      const userSub = user?.sub;
      const userRole = user?.role;

      const meta: Record<string, unknown> = {
        requestId,
        method: req.method,
        path: safePath(req),
        statusCode: res.statusCode,
        durationMs: Math.round(durationMs * 10) / 10
      };

      if (userSub) meta.userSub = userSub;
      if (userRole) meta.userRole = userRole;

      // Keep noise down: log 5xx as error, 4xx as warn, otherwise info.
      if (res.statusCode >= 500) {
        logger.error('HTTP request failed', meta);
      } else if (res.statusCode >= 400) {
        logger.warn('HTTP request client error', meta);
      } else {
        logger.log('HTTP request', meta);
      }
    });

    next();
  };
}
