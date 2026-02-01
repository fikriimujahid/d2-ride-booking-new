import { Module } from '@nestjs/common';
import { AdminHealthController } from './admin-health.controller';
import { DriverHealthController } from './driver-health.controller';
import { PassengerHealthController } from './passenger-health.controller';

@Module({
  controllers: [AdminHealthController, DriverHealthController, PassengerHealthController]
})
export class HealthModule {}
