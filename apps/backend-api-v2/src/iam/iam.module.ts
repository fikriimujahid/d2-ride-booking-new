import { Module } from '@nestjs/common';
import { AdminUsersModule } from './admin-users/admin-users.module';
import { RolesModule } from './roles/roles.module';
import { PermissionsModule } from './permissions/permissions.module';
import { RbacModule } from './rbac/rbac.module';
import { AccessContextModule } from './access-context/access-context.module';

@Module({
  imports: [AdminUsersModule, RolesModule, PermissionsModule, RbacModule, AccessContextModule]
})
export class IamModule {}
