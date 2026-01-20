import { Injectable } from '@nestjs/common';
import { JsonLogger } from './logging/json-logger.service';

@Injectable()
export class AppService {
  constructor(private readonly logger: JsonLogger) {}

  health() {
    this.logger.log('health probe served');
    return { status: 'ok', service: 'backend-api', timestamp: new Date().toISOString() };
  }
}
