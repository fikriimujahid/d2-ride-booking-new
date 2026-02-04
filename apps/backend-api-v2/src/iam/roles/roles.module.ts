import { Module } from '@nestjs/common';
import { RoleController } from './role.controller';
import { RoleService } from './role.service';
import { RbacModule } from '../rbac/rbac.module';

@Module({
  imports: [RbacModule],
  controllers: [RoleController],
  providers: [RoleService],
  exports: [RoleService]
})
export class RolesModule {}
