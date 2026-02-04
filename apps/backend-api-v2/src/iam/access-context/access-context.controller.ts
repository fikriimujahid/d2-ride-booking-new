import { Controller, Get, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { ApiBearerAuth, ApiOkResponse, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../../auth/jwt-auth.guard';
import { SystemGroupGuard } from '../../auth/system-group.guard';
import { SystemGroup } from '../../auth/decorators/system-group.decorator';
import { SystemGroup as SystemGroupEnum } from '../../auth/enums/system-group.enum';
import { AccessContextService } from './access-context.service';
import type { AdminAccessContext } from './types';

@ApiTags('admin')
@ApiBearerAuth('bearer')
@Controller('admin')
@UseGuards(JwtAuthGuard, SystemGroupGuard)
export class AccessContextController {
  constructor(private readonly accessContext: AccessContextService) {}

  /**
   * Returns admin access context for UI bootstrap.
   *
   * NOTE: This endpoint intentionally does NOT apply RBAC guard.
   * RBAC is still enforced on all protected endpoints.
   */
  @Get('me')
  @SystemGroup(SystemGroupEnum.ADMIN)
  @ApiOkResponse({ description: 'Admin access context bootstrap' })
  async me(@Req() req: Request): Promise<AdminAccessContext> {
    // JwtAuthGuard guarantees user exists; SystemGroupGuard guarantees ADMIN.
    return this.accessContext.getAdminMe(req.user!);
  }
}
