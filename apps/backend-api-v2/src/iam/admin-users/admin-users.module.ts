// Import NestJS Module decorator
import { Module } from '@nestjs/common';
// Import admin user controller
import { AdminUserController } from './admin-user.controller';
// Import admin user service
import { AdminUserService } from './admin-user.service';
// Import RBAC module for permission enforcement
import { RbacModule } from '../rbac/rbac.module';

/**
 * AdminUsersModule - Module for managing admin users in RBAC system
 * Provides REST API for CRUD operations on admin_user records.
 * Includes role assignment and status management.
 * 
 * Routes: /admin/admin-users
 * Exports: AdminUserService for use in other modules
 */
@Module({
  // Import RBAC module for permission resolution
  imports: [RbacModule],
  // Register REST API controller
  controllers: [AdminUserController],
  // Register business logic service
  providers: [AdminUserService],
  // Export service for dependency injection in other modules
  exports: [AdminUserService]
})
export class AdminUsersModule {}
