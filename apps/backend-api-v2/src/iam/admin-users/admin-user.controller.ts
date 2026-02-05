// Import NestJS controller decorators
import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Put,
  Req,
  UseGuards
} from '@nestjs/common';
// Import Express Request type
import type { Request } from 'express';
// Import Swagger decorators for API documentation
import { ApiBearerAuth, ApiTags, ApiBody } from '@nestjs/swagger';
// Import authentication and authorization guards
import { JwtAuthGuard } from '../../auth/jwt-auth.guard';
import { SystemGroupGuard } from '../../auth/system-group.guard';
import { SystemGroup as SystemGroupMeta } from '../../auth/decorators/system-group.decorator';
import { SystemGroup } from '../../auth/enums/system-group.enum';
import { RbacGuard } from '../rbac/rbac.guard';
import { RequirePermissions } from '../rbac/permission.decorator';
// Import DTOs
import { CreateAdminUserDto } from './dto/create-admin-user.dto';
import { UpdateAdminUserDto } from './dto/update-admin-user.dto';
import { ReplaceAdminUserRolesDto } from './dto/replace-admin-user-roles.dto';
// Import admin user service
import { AdminUserService } from './admin-user.service';

/**
 * AdminUserController - REST API controller for managing admin users
 * Routes: /admin/admin-users
 * 
 * Manages admin_user records that link Cognito users to RBAC system.
 * Provides CRUD operations and role assignment.
 * 
 * All endpoints require:
 * - Valid JWT (JwtAuthGuard)
 * - ADMIN system group (SystemGroupGuard)
 * - Specific RBAC permissions (RbacGuard + @RequirePermissions)
 */
@ApiTags('admin-iam')  // Swagger group
@ApiBearerAuth('bearer')  // Require Bearer token
@Controller('admin/admin-users')
@SystemGroupMeta(SystemGroup.ADMIN)  // All routes require ADMIN group
@UseGuards(JwtAuthGuard, SystemGroupGuard, RbacGuard)  // Apply guard chain
export class AdminUserController {
  /**
   * Constructor - injects admin user service
   * @param admins - AdminUserService for business logic
   */
  constructor(private readonly admins: AdminUserService) {}

  /**
   * GET /admin/admin-users - List all active admin users
   * Requires: admin-user:view permission
   * Returns array of admin users with their assigned roles
   */
  @Get()
  @RequirePermissions('admin-user:view')
  list() {
    return this.admins.list();
  }

  /**
   * GET /admin/admin-users/:id - Get single admin user by ID
   * Requires: admin-user:read permission
   * Returns admin user with assigned roles
   * @param id - Admin user UUID
   */
  @Get(':id')
  @RequirePermissions('admin-user:read')
  get(@Param('id') id: string) {
    return this.admins.getById(id);
  }

  /**
   * POST /admin/admin-users - Create new admin user
   * Requires: admin-user:create permission
   * 
   * Creates link between Cognito user and RBAC system.
   * If admin user was soft-deleted, restores it.
   * Logs audit trail of creation.
   * 
   * @param dto - Admin user creation data (cognitoSub, email, status)
   * @param req - Express request with actor info for audit
   * @returns Created admin user record
   */
  @Post()
  @RequirePermissions('admin-user:create')
    @ApiBody({
      type: CreateAdminUserDto,
      examples: {
        basic: {
          summary: 'Create admin user',
          value: {
            cognitoSub: '00000000-0000-0000-0000-000000000000',
            email: 'admin@example.com',
            status: 'ACTIVE'
          }
        }
      }
    })
  create(@Body() dto: CreateAdminUserDto, @Req() req: Request) {
    return this.admins.create({
      cognitoSub: dto.cognitoSub,
      email: dto.email,
      status: dto.status,
      actorAdminUserId: req.rbac!.adminUserId,
      request: req
    });
  }

  /**
   * PUT /admin/admin-users/:id - Update admin user
   * Requires: admin-user:update permission
   * 
   * Updates email or status of admin user.
   * Logs audit trail with before/after state.
   * 
   * @param id - Admin user UUID
   * @param dto - Fields to update (email, status)
   * @param req - Express request with actor info for audit
   * @returns Updated admin user record
   */
  @Put(':id')
  @RequirePermissions('admin-user:update')
    @ApiBody({
      type: UpdateAdminUserDto,
      examples: {
        update: {
          summary: 'Update admin user',
          value: {
            email: 'admin2@example.com',
            status: 'DISABLED'
          }
        }
      }
    })
  update(@Param('id') id: string, @Body() dto: UpdateAdminUserDto, @Req() req: Request) {
    return this.admins.update({
      id,
      email: dto.email,
      status: dto.status,
      actorAdminUserId: req.rbac!.adminUserId,
      request: req
    });
  }

  /**
   * DELETE /admin/admin-users/:id - Soft delete admin user
   * Requires: admin-user:delete permission
   * 
   * Soft deletes admin user (sets deletedAt timestamp).
   * User can be restored via create endpoint with same cognitoSub.
   * Logs audit trail of deletion.
   * 
   * @param id - Admin user UUID
   * @param req - Express request with actor info for audit
   * @returns Success indicator
   */
  @Delete(':id')
  @RequirePermissions('admin-user:delete')
  async delete(@Param('id') id: string, @Req() req: Request) {
    await this.admins.softDelete({
      id,
      actorAdminUserId: req.rbac!.adminUserId,
      request: req
    });
    return { ok: true };
  }

  /**
   * POST /admin/admin-users/:id/roles - Replace admin user's roles
   * Requires: admin-user:assign-role permission
   * 
   * Replaces entire role assignment (not additive).
   * Removes all existing roles and assigns new ones.
   * Empty array removes all roles.
   * Validates that all role IDs exist and are active.
   * Logs audit trail with before/after role IDs.
   * 
   * @param id - Admin user UUID
   * @param dto - Array of role UUIDs to assign
   * @param req - Express request with actor info for audit
   * @returns Success indicator
   */
  @Post(':id/roles')
  @RequirePermissions('admin-user:assign-role')
    @ApiBody({
      type: ReplaceAdminUserRolesDto,
      examples: {
        replace: {
          summary: 'Replace admin user roles',
          value: {
            roleIds: [
              '11111111-1111-1111-1111-111111111111',
              '22222222-2222-2222-2222-222222222222'
            ]
          }
        }
      }
    })
  async replaceRoles(@Param('id') id: string, @Body() dto: ReplaceAdminUserRolesDto, @Req() req: Request) {
    await this.admins.replaceRoles({
      adminUserId: id,
      roleIds: dto.roleIds,
      actorAdminUserId: req.rbac!.adminUserId,
      request: req
    });
    return { ok: true };
  }
}
