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
import type { Request } from 'express';
import { ApiBearerAuth, ApiTags, ApiBody } from '@nestjs/swagger';
import { JwtAuthGuard } from '../../auth/jwt-auth.guard';
import { SystemGroupGuard } from '../../auth/system-group.guard';
import { SystemGroup as SystemGroupMeta } from '../../auth/decorators/system-group.decorator';
import { SystemGroup } from '../../auth/enums/system-group.enum';
import { RbacGuard } from '../rbac/rbac.guard';
import { RequirePermissions } from '../rbac/permission.decorator';
import { CreateRoleDto } from './dto/create-role.dto';
import { UpdateRoleDto } from './dto/update-role.dto';
import { ReplaceRolePermissionsDto } from './dto/replace-role-permissions.dto';
import { RoleService } from './role.service';

@ApiTags('admin-iam')
@ApiBearerAuth('bearer')
@Controller('admin/roles')
@SystemGroupMeta(SystemGroup.ADMIN)
@UseGuards(JwtAuthGuard, SystemGroupGuard, RbacGuard)
export class RoleController {
  constructor(private readonly roles: RoleService) {}

  @Get()
  @RequirePermissions('role:view')
  list() {
    return this.roles.list();
  }

  @Get(':id')
  @RequirePermissions('role:read')
  get(@Param('id') id: string) {
    return this.roles.getById(id);
  }

  @Post()
  @RequirePermissions('role:create')
    @ApiBody({
      type: CreateRoleDto,
      examples: {
        basic: {
          summary: 'Create role',
          value: {
            name: 'OPERATION_MANAGER',
            description: 'Can manage operations'
          }
        }
      }
    })
  create(@Body() dto: CreateRoleDto, @Req() req: Request) {
    return this.roles.create({
      name: dto.name,
      description: dto.description,
      actorAdminUserId: req.rbac!.adminUserId,
      request: req
    });
  }

  @Put(':id')
  @RequirePermissions('role:update')
    @ApiBody({
      type: UpdateRoleDto,
      examples: {
        update: {
          summary: 'Update role',
          value: {
            name: 'ANALYST',
            description: 'Can view analytics only'
          }
        }
      }
    })
  update(@Param('id') id: string, @Body() dto: UpdateRoleDto, @Req() req: Request) {
    return this.roles.update({
      id,
      name: dto.name,
      description: dto.description,
      actorAdminUserId: req.rbac!.adminUserId,
      request: req
    });
  }

  @Delete(':id')
  @RequirePermissions('role:delete')
  async delete(@Param('id') id: string, @Req() req: Request) {
    await this.roles.softDelete({
      id,
      actorAdminUserId: req.rbac!.adminUserId,
      request: req
    });
    return { ok: true };
  }

  @Post(':id/permissions')
  @RequirePermissions('role:assign-permission')
    @ApiBody({
      type: ReplaceRolePermissionsDto,
      examples: {
        replace: {
          summary: 'Replace role permissions',
          value: {
            permissionIds: [
              'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
            ]
          }
        }
      }
    })
  async replacePermissions(@Param('id') id: string, @Body() dto: ReplaceRolePermissionsDto, @Req() req: Request) {
    await this.roles.replacePermissions({
      roleId: id,
      permissionIds: dto.permissionIds,
      actorAdminUserId: req.rbac!.adminUserId,
      request: req
    });
    return { ok: true };
  }
}
