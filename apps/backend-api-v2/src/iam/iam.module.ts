// Import Module decorator
import { Module } from '@nestjs/common';
// Import IAM feature modules
import { AdminUsersModule } from './admin-users/admin-users.module';
import { RolesModule } from './roles/roles.module';
import { PermissionsModule } from './permissions/permissions.module';
import { RbacModule } from './rbac/rbac.module';
import { AccessContextModule } from './access-context/access-context.module';

/**
 * IamModule - Identity and Access Management module
 * Aggregates all IAM-related feature modules:
 * - Admin user management
 * - Role management  
 * - Permission management
 * - RBAC enforcement
 * - Access context inspection
 * 
 * Provides comprehensive role-based access control (RBAC) for admin users
 */
@Module({
  imports: [AdminUsersModule, RolesModule, PermissionsModule, RbacModule, AccessContextModule]
})
export class IamModule {}
