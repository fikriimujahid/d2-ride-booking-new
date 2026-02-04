import { Module } from '@nestjs/common';
import { PermissionService } from './permission.service';
import { RbacGuard } from './rbac.guard';
import { AdminRbacExampleController } from './rbac-example.controller';

@Module({
  controllers: [AdminRbacExampleController],
  providers: [PermissionService, RbacGuard],
  exports: [PermissionService, RbacGuard]
})
export class RbacModule {}
