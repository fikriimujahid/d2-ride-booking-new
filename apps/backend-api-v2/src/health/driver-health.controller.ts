// Import NestJS decorators for controllers and guards
import { Controller, Get, UseGuards } from '@nestjs/common';
// Import SystemGroup decorator to restrict access
import { SystemGroup } from '../auth/decorators/system-group.decorator';
// Import JWT authentication guard
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
// Import system group authorization guard
import { SystemGroupGuard } from '../auth/system-group.guard';
// Import SystemGroup enum
import { SystemGroup as SystemGroupEnum } from '../auth/enums/system-group.enum';

/**
 * DriverHealthController - Health check endpoint for driver system
 * Route: GET /driver/health
 * Requires authentication and DRIVER system group membership
 */
@Controller('driver')
export class DriverHealthController {
  /**
   * Health check endpoint for driver system
   * Used by load balancers and monitoring to verify service availability
   * @returns Simple health status object
   */
  @Get('health')
  @SystemGroup(SystemGroupEnum.DRIVER)  // Require DRIVER group membership
  @UseGuards(JwtAuthGuard, SystemGroupGuard)  // Apply authentication and authorization
  health() {
    return { ok: true, system: 'driver' };
  }
}
