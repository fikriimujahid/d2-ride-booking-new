// Import NestJS controller decorators
import { Controller, Get, Req, UseGuards } from '@nestjs/common';
// Import Express Request type
import type { Request } from 'express';
// Import Swagger decorators for API documentation
import { ApiBearerAuth, ApiOkResponse, ApiTags } from '@nestjs/swagger';
// Import authentication guards
import { JwtAuthGuard } from '../../auth/jwt-auth.guard';
import { SystemGroupGuard } from '../../auth/system-group.guard';
import { SystemGroup } from '../../auth/decorators/system-group.decorator';
import { SystemGroup as SystemGroupEnum } from '../../auth/enums/system-group.enum';
// Import access context service
import { AccessContextService } from './access-context.service';
// Import access context types
import type { AdminAccessContext } from './types';

/**
 * AccessContextController - REST API controller for admin access context
 * Provides /admin/me endpoint for admin UI bootstrap.
 * 
 * This endpoint returns complete authorization snapshot including:
 * - User identity (id, email, display name)
 * - Assigned roles
 * - Effective permissions (flattened from roles)
 * - Module access map for UI visibility control
 * 
 * Routes: /admin/me
 * Security: JWT + ADMIN group (no RBAC guard - this is the bootstrap endpoint)
 */
@ApiTags('admin')  // Swagger group
@ApiBearerAuth('bearer')  // Require Bearer token
@Controller('admin')
@UseGuards(JwtAuthGuard, SystemGroupGuard)  // Apply authentication guards
export class AccessContextController {
  /**
   * Constructor - injects access context service
   * @param accessContext - Service for building access context
   */
  constructor(private readonly accessContext: AccessContextService) {}

  /**
   * GET /admin/me - Returns admin access context for UI bootstrap.
   * Called by frontend on login/refresh to get complete authorization state.
   * 
   * NOTE: This endpoint intentionally does NOT apply RBAC guard.
   * - Used for initial UI bootstrap before permissions are loaded
   * - RBAC is still enforced on all other protected endpoints
   * - Guards ensure user is authenticated and in ADMIN Cognito group
   * 
   * @param req - Express request with authenticated user
   * @returns Complete admin access context for UI
   */
  @Get('me')
  @SystemGroup(SystemGroupEnum.ADMIN)  // Require ADMIN Cognito group
  @ApiOkResponse({ description: 'Admin access context bootstrap' })
  async me(@Req() req: Request): Promise<AdminAccessContext> {
    // JwtAuthGuard guarantees user exists; SystemGroupGuard guarantees ADMIN.
    return this.accessContext.getAdminMe(req.user!);
  }
}
