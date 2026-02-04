import { Module } from '@nestjs/common';
import { PermissionController } from './permission.controller';
import { AdminPermissionService } from './permission.service';
import { RbacModule } from '../rbac/rbac.module';

@Module({
  imports: [RbacModule],
  controllers: [PermissionController],
  providers: [AdminPermissionService],
  exports: [AdminPermissionService]
})
export class PermissionsModule {}
