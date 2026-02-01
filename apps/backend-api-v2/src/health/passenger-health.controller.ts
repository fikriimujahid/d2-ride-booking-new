import { Controller, Get, UseGuards } from '@nestjs/common';
import { SystemGroup } from '../auth/decorators/system-group.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SystemGroupGuard } from '../auth/system-group.guard';
import { SystemGroup as SystemGroupEnum } from '../auth/enums/system-group.enum';

@Controller('passenger')
export class PassengerHealthController {
  @Get('health')
  @SystemGroup(SystemGroupEnum.PASSENGER)
  @UseGuards(JwtAuthGuard, SystemGroupGuard)
  health() {
    return { ok: true, system: 'passenger' };
  }
}
