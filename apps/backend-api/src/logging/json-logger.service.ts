import { ConsoleLogger, Injectable, LogLevel } from '@nestjs/common';

/**
 * Simple JSON logger to keep CloudWatch Logs parseable without extra agents.
 * Writes to stdout with {level,msg,context,...meta} shape.
 */
@Injectable()
export class JsonLogger extends ConsoleLogger {
  constructor(context?: string) {
    super(context ?? 'backend-api');
  }

  private nowIso() {
    return new Date().toISOString();
  }

  private normalizeError(error: unknown) {
    if (error instanceof Error) {
      return {
        name: error.name,
        message: error.message,
        stack: error.stack
      };
    }

    if (typeof error === 'object' && error !== null) {
      // Best-effort serialization for non-Error throwables.
      try {
        return JSON.parse(JSON.stringify(error)) as Record<string, unknown>;
      } catch {
        return { value: String(error) };
      }
    }

    return { value: String(error) };
  }

  private normalizeMessage(message: unknown) {
    if (message instanceof Error) {
      return { msg: message.message, error: this.normalizeError(message) };
    }
    return { msg: message };
  }

  log(message: unknown, context?: string): void;
  log(message: unknown, meta?: Record<string, unknown>): void;
  log(message: unknown, metaOrContext?: string | Record<string, unknown>) {
    const context = typeof metaOrContext === 'string' ? metaOrContext : this.context;
    const meta = typeof metaOrContext === 'string' ? {} : metaOrContext;
    super.log(
      JSON.stringify({ ts: this.nowIso(), level: 'info', context, ...this.normalizeMessage(message), ...(meta ?? {}) })
    );
  }

  warn(message: unknown, context?: string): void;
  warn(message: unknown, meta?: Record<string, unknown>): void;
  warn(message: unknown, metaOrContext?: string | Record<string, unknown>) {
    const context = typeof metaOrContext === 'string' ? metaOrContext : this.context;
    const meta = typeof metaOrContext === 'string' ? {} : metaOrContext;
    super.warn(
      JSON.stringify({ ts: this.nowIso(), level: 'warn', context, ...this.normalizeMessage(message), ...(meta ?? {}) })
    );
  }

  error(message: unknown, stack?: string, context?: string): void;
  error(message: unknown, meta?: Record<string, unknown>): void;
  error(message: unknown, stackOrMeta?: string | Record<string, unknown>, maybeContext?: string) {
    const stack = typeof stackOrMeta === 'string' ? stackOrMeta : undefined;
    const context = typeof maybeContext === 'string' ? maybeContext : this.context;
    const meta = typeof stackOrMeta === 'string' ? {} : (stackOrMeta ?? {});

    super.error(
      JSON.stringify({
        ts: this.nowIso(),
        level: 'error',
        context,
        ...this.normalizeMessage(message),
        ...(stack ? { stack } : {}),
        ...(meta ?? {})
      })
    );
  }

  debug(message: unknown, context?: string): void;
  debug(message: unknown, meta?: Record<string, unknown>): void;
  debug(message: unknown, metaOrContext?: string | Record<string, unknown>) {
    const context = typeof metaOrContext === 'string' ? metaOrContext : this.context;
    const meta = typeof metaOrContext === 'string' ? {} : metaOrContext;
    super.debug(
      JSON.stringify({ ts: this.nowIso(), level: 'debug', context, ...this.normalizeMessage(message), ...(meta ?? {}) })
    );
  }

  verbose(message: unknown, context?: string): void;
  verbose(message: unknown, meta?: Record<string, unknown>): void;
  verbose(message: unknown, metaOrContext?: string | Record<string, unknown>) {
    const context = typeof metaOrContext === 'string' ? metaOrContext : this.context;
    const meta = typeof metaOrContext === 'string' ? {} : metaOrContext;
    super.verbose(
      JSON.stringify({ ts: this.nowIso(), level: 'verbose', context, ...this.normalizeMessage(message), ...(meta ?? {}) })
    );
  }

  /** Keeps Nest from downgrading log levels when bufferLogs=true. */
  setLogLevels(levels: LogLevel[]) {
    super.setLogLevels(levels);
  }
}
