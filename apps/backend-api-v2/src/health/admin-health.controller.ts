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
 * AdminHealthController - Health check endpoint for admin system
 * Route: GET /admin/health
 * Requires authentication and ADMIN system group membership
 */
@Controller('admin')
export class AdminHealthController {
  /**
   * Health check endpoint for admin system
   * Used by load balancers and monitoring to verify service availability
   * @returns Simple health status object
   */
  @Get('health')
  @SystemGroup(SystemGroupEnum.ADMIN)  // Require ADMIN group membership
  @UseGuards(JwtAuthGuard, SystemGroupGuard)  // Apply authentication and authorization
  health() {
    return { ok: true, system: 'admin' };
  }
}
