// Import Module decorator
import { Module } from '@nestjs/common';
// Import role controller for REST API
import { RoleController } from './role.controller';
// Import role service for business logic
import { RoleService } from './role.service';
// Import RBAC module for authorization
import { RbacModule } from '../rbac/rbac.module';

/**
 * RolesModule - Manages RBAC roles
 * Roles are collections of permissions that can be assigned to admin users
 * Provides CRUD operations and permission assignment functionality
 */
@Module({
  imports: [RbacModule],  // Import for RbacGuard
  controllers: [RoleController],  // REST API endpoints
  providers: [RoleService],  // Business logic
  exports: [RoleService]  // Export for use in other modules
})
export class RolesModule {}
