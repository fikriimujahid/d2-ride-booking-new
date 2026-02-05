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
// Import Swagger/OpenAPI decorators for API documentation
import { ApiBearerAuth, ApiTags, ApiBody } from '@nestjs/swagger';
// Import authentication and authorization guards
import { JwtAuthGuard } from '../../auth/jwt-auth.guard';
import { SystemGroupGuard } from '../../auth/system-group.guard';
import { SystemGroup as SystemGroupMeta } from '../../auth/decorators/system-group.decorator';
import { SystemGroup } from '../../auth/enums/system-group.enum';
import { RbacGuard } from '../rbac/rbac.guard';
import { RequirePermissions } from '../rbac/permission.decorator';
// Import DTOs for request validation
import { CreatePermissionDto } from './dto/create-permission.dto';
import { UpdatePermissionDto } from './dto/update-permission.dto';
// Import permission service
import { AdminPermissionService } from './permission.service';

/**
 * PermissionController - REST API controller for managing RBAC permissions
 * Routes: /admin/permissions
 * 
 * All endpoints require:
 * - Valid JWT (JwtAuthGuard)
 * - ADMIN system group (SystemGroupGuard)
 * - Specific RBAC permissions (RbacGuard + @RequirePermissions)
 */
@ApiTags('admin-iam')  // Group in Swagger UI
@ApiBearerAuth('bearer')  // Require Bearer token in Swagger
@Controller('admin/permissions')
@SystemGroupMeta(SystemGroup.ADMIN)  // All routes require ADMIN group
@UseGuards(JwtAuthGuard, SystemGroupGuard, RbacGuard)  // Apply guard chain
export class PermissionController {
  /**
   * Constructor - injects permission service
   * @param permissions - AdminPermissionService for business logic
   */
  constructor(private readonly permissions: AdminPermissionService) {}

  /**
   * List all permissions
   * GET /admin/permissions
   * Requires: permission:view
   */
  @Get()
  @RequirePermissions('permission:view')
  list() {
    return this.permissions.list();
  }

  /**
   * Get a single permission by ID
   * GET /admin/permissions/:id
   * Requires: permission:read
   */
  @Get(':id')
  @RequirePermissions('permission:read')
  get(@Param('id') id: string) {
    return this.permissions.getById(id);
  }

  /**
   * Create a new permission
   * POST /admin/permissions
   * Requires: permission:create
   * Logs action to audit log
   */
  @Post()
  @RequirePermissions('permission:create')
    @ApiBody({  // Swagger documentation
      type: CreatePermissionDto,
      examples: {
        basic: {
          summary: 'Create permission',
          value: {
            key: 'driver:read',
            description: 'Read driver data'
          }
        }
      }
    })
  create(@Body() dto: CreatePermissionDto, @Req() req: Request) {
    return this.permissions.create({
      key: dto.key,
      description: dto.description,
      actorAdminUserId: req.rbac!.adminUserId,  // From RBAC resolution
      request: req  // For audit logging (IP, user-agent, etc.)
    });
  }

  /**
   * Update an existing permission
   * PUT /admin/permissions/:id
   * Requires: permission:update
   * Logs action to audit log with before/after state
   */
  @Put(':id')
  @RequirePermissions('permission:update')
    @ApiBody({  // Swagger documentation
      type: UpdatePermissionDto,
      examples: {
        update: {
          summary: 'Update permission',
          value: {
            key: 'driver:update',
            description: 'Update driver data'
          }
        }
      }
    })
  update(@Param('id') id: string, @Body() dto: UpdatePermissionDto, @Req() req: Request) {
    return this.permissions.update({
      id,
      key: dto.key,
      description: dto.description,
      actorAdminUserId: req.rbac!.adminUserId,
      request: req
    });
  }

  /**
   * Soft-delete a permission
   * DELETE /admin/permissions/:id
   * Requires: permission:delete
   * Prevents deletion if permission is assigned to any role
   * Logs action to audit log
   */
  @Delete(':id')
  @RequirePermissions('permission:delete')
  async delete(@Param('id') id: string, @Req() req: Request) {
    await this.permissions.softDelete({
      id,
      actorAdminUserId: req.rbac!.adminUserId,
      request: req
    });
    return { ok: true };
  }
}
