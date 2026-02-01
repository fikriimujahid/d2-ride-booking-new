import { Controller, Get, UseGuards } from '@nestjs/common';
import { SystemGroup } from '../auth/decorators/system-group.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SystemGroupGuard } from '../auth/system-group.guard';
import { SystemGroup as SystemGroupEnum } from '../auth/enums/system-group.enum';

@Controller('driver')
export class DriverHealthController {
  @Get('health')
  @SystemGroup(SystemGroupEnum.DRIVER)
  @UseGuards(JwtAuthGuard, SystemGroupGuard)
  health() {
    return { ok: true, system: 'driver' };
  }
}
