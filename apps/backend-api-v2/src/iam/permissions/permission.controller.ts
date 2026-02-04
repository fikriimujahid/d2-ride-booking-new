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
import { CreatePermissionDto } from './dto/create-permission.dto';
import { UpdatePermissionDto } from './dto/update-permission.dto';
import { AdminPermissionService } from './permission.service';

@ApiTags('admin-iam')
@ApiBearerAuth('bearer')
@Controller('admin/permissions')
@SystemGroupMeta(SystemGroup.ADMIN)
@UseGuards(JwtAuthGuard, SystemGroupGuard, RbacGuard)
export class PermissionController {
  constructor(private readonly permissions: AdminPermissionService) {}

  @Get()
  @RequirePermissions('permission:view')
  list() {
    return this.permissions.list();
  }

  @Get(':id')
  @RequirePermissions('permission:read')
  get(@Param('id') id: string) {
    return this.permissions.getById(id);
  }

  @Post()
  @RequirePermissions('permission:create')
    @ApiBody({
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
      actorAdminUserId: req.rbac!.adminUserId,
      request: req
    });
  }

  @Put(':id')
  @RequirePermissions('permission:update')
    @ApiBody({
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
