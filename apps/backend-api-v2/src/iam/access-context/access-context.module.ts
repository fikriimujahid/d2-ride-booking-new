import { Module } from '@nestjs/common';
import { AccessContextController } from './access-context.controller';
import { AccessContextService } from './access-context.service';

@Module({
  controllers: [AccessContextController],
  providers: [AccessContextService]
})
export class AccessContextModule {}
