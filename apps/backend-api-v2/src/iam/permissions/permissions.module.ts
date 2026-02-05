// Import Module decorator
import { Module } from '@nestjs/common';
// Import permission controller for REST API endpoints
import { PermissionController } from './permission.controller';
// Import admin permission service for CRUD operations
import { AdminPermissionService } from './permission.service';
// Import RBAC module for authorization
import { RbacModule } from '../rbac/rbac.module';

/**
 * PermissionsModule - Manages RBAC permissions
 * Provides CRUD operations for permissions (e.g., 'user:create', 'report:view')
 * Permissions are assigned to roles, which are then assigned to admin users
 */
@Module({
  imports: [RbacModule],  // Import for RbacGuard and permission checking
  controllers: [PermissionController],  // REST API endpoints
  providers: [AdminPermissionService],  // Business logic service
  exports: [AdminPermissionService]     // Export for use in other modules
})
export class PermissionsModule {}
