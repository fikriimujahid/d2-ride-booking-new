// Import Module decorator
import { Module } from '@nestjs/common';
// Import health check controllers for different system groups
import { AdminHealthController } from './admin-health.controller';
import { DriverHealthController } from './driver-health.controller';
import { PassengerHealthController } from './passenger-health.controller';

/**
 * HealthModule - Provides health check endpoints for monitoring
 * Exposes system-specific health endpoints for admin, driver, and passenger systems
 * Used by load balancers, monitoring tools, and deployment pipelines
 */
@Module({
  // Register health check controllers for each system group
  controllers: [AdminHealthController, DriverHealthController, PassengerHealthController]
})
export class HealthModule {}
