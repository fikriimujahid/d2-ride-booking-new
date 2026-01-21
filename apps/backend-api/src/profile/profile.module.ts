import { Module } from '@nestjs/common';
import { ProfileController } from './profile.controller';
import { ProfileService } from './profile.service';
import { DatabaseService } from '../database/database.service';
import { JsonLogger } from '../logging/json-logger.service';

@Module({
  controllers: [ProfileController],
  providers: [ProfileService, DatabaseService, JsonLogger],
  exports: [ProfileService]
})
export class ProfileModule {}
