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
import { CreateAdminUserDto } from './dto/create-admin-user.dto';
import { UpdateAdminUserDto } from './dto/update-admin-user.dto';
import { ReplaceAdminUserRolesDto } from './dto/replace-admin-user-roles.dto';
import { AdminUserService } from './admin-user.service';

@ApiTags('admin-iam')
@ApiBearerAuth('bearer')
@Controller('admin/admin-users')
@SystemGroupMeta(SystemGroup.ADMIN)
@UseGuards(JwtAuthGuard, SystemGroupGuard, RbacGuard)
export class AdminUserController {
  constructor(private readonly admins: AdminUserService) {}

  @Get()
  @RequirePermissions('admin-user:view')
  list() {
    return this.admins.list();
  }

  @Get(':id')
  @RequirePermissions('admin-user:read')
  get(@Param('id') id: string) {
    return this.admins.getById(id);
  }

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
