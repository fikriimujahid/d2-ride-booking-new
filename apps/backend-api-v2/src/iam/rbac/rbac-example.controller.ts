import { Controller, Get, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../auth/jwt-auth.guard';
import { SystemGroupGuard } from '../../auth/system-group.guard';
import { SystemGroup as SystemGroupMeta } from '../../auth/decorators/system-group.decorator';
import { SystemGroup } from '../../auth/enums/system-group.enum';
import { RequirePermissions } from './permission.decorator';
import { RbacGuard } from './rbac.guard';

@Controller('admin')
@SystemGroupMeta(SystemGroup.ADMIN)
@UseGuards(JwtAuthGuard, SystemGroupGuard, RbacGuard)
export class AdminRbacExampleController {
  @Get('dashboard')
  @RequirePermissions('dashboard:view')
  dashboard() {
    return { ok: true, feature: 'dashboard' };
  }

  @Get('analytics')
  @RequirePermissions('analytics:view')
  analytics() {
    return { ok: true, feature: 'analytics' };
  }

  @Post('reports/generate')
  @RequirePermissions('report:generate')
  generateReport() {
    return { ok: true, feature: 'report:generate' };
  }

  @Get('drivers')
  @RequirePermissions('driver:read', 'driver:manage')
  driversReadOrManage() {
    return { ok: true, feature: 'driver:list' };
  }
}
