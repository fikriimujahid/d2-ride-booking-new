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
 * PassengerHealthController - Health check endpoint for passenger system
 * Route: GET /passenger/health
 * Requires authentication and PASSENGER system group membership
 */
@Controller('passenger')
export class PassengerHealthController {
  /**
   * Health check endpoint for passenger system
   * Used by load balancers and monitoring to verify service availability
   * @returns Simple health status object
   */
  @Get('health')
  @SystemGroup(SystemGroupEnum.PASSENGER)  // Require PASSENGER group membership
  @UseGuards(JwtAuthGuard, SystemGroupGuard)  // Apply authentication and authorization
  health() {
    return { ok: true, system: 'passenger' };
  }
}
