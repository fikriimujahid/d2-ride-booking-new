// Import NestJS controller decorators
import { Controller, Get, Post, UseGuards } from '@nestjs/common';
// Import authentication guard
import { JwtAuthGuard } from '../../auth/jwt-auth.guard';
// Import system group authorization guard
import { SystemGroupGuard } from '../../auth/system-group.guard';
// Import system group decorator
import { SystemGroup as SystemGroupMeta } from '../../auth/decorators/system-group.decorator';
// Import SystemGroup enum
import { SystemGroup } from '../../auth/enums/system-group.enum';
// Import RBAC permission decorator
import { RequirePermissions } from './permission.decorator';
// Import RBAC authorization guard
import { RbacGuard } from './rbac.guard';

/**
 * AdminRbacExampleController - Example controller demonstrating RBAC usage patterns
 * 
 * All routes require:
 * 1. Valid JWT token (JwtAuthGuard)
 * 2. ADMIN system group (SystemGroupGuard)
 * 3. Specific permissions (RbacGuard + @RequirePermissions)
 * 
 * This controller serves as a reference implementation for RBAC-protected endpoints
 */
@Controller('admin')
@SystemGroupMeta(SystemGroup.ADMIN)  // All routes require ADMIN group
@UseGuards(JwtAuthGuard, SystemGroupGuard, RbacGuard)  // Apply guard chain to all routes
export class AdminRbacExampleController {
  /**
   * Dashboard endpoint - requires dashboard:view permission
   * GET /admin/dashboard
   */
  @Get('dashboard')
  @RequirePermissions('dashboard:view')  // Specific permission required
  dashboard() {
    return { ok: true, feature: 'dashboard' };
  }

  /**
   * Analytics endpoint - requires analytics:view permission
   * GET /admin/analytics
   */
  @Get('analytics')
  @RequirePermissions('analytics:view')
  analytics() {
    return { ok: true, feature: 'analytics' };
  }

  /**
   * Report generation endpoint - requires report:generate permission
   * POST /admin/reports/generate
   */
  @Post('reports/generate')
  @RequirePermissions('report:generate')
  generateReport() {
    return { ok: true, feature: 'report:generate' };
  }

  /**
   * Driver management endpoint - requires EITHER driver:read OR driver:manage
   * GET /admin/drivers
   * Demonstrates OR semantics: user needs at least one of the listed permissions
   */
  @Get('drivers')
  @RequirePermissions('driver:read', 'driver:manage')  // Any-of (OR)
  driversReadOrManage() {
    return { ok: true, feature: 'driver:list' };
  }
}
