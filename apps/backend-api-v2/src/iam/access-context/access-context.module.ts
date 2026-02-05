// Import NestJS Module decorator
import { Module } from '@nestjs/common';
// Import access context controller
import { AccessContextController } from './access-context.controller';
// Import access context service
import { AccessContextService } from './access-context.service';

/**
 * AccessContextModule - Module for admin UI access context bootstrap
 * Provides /admin/me endpoint for admin user authorization snapshot
 * Used by frontend to determine UI visibility and permissions
 */
@Module({
  // Register REST API controller
  controllers: [AccessContextController],
  // Register business logic service
  providers: [AccessContextService]
})
export class AccessContextModule {}
