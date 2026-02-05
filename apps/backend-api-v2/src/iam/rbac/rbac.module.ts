// Import Module decorator
import { Module } from '@nestjs/common';
// Import RBAC permission resolution service
import { PermissionService } from './permission.service';
// Import RBAC authorization guard
import { RbacGuard } from './rbac.guard';
// Import example controller demonstrating RBAC usage
import { AdminRbacExampleController } from './rbac-example.controller';

/**
 * RbacModule - Role-Based Access Control module
 * Provides fine-grained permission checking for admin users
 * Exports PermissionService and RbacGuard for use in other modules
 */
@Module({
  controllers: [AdminRbacExampleController],  // Demo controller showing RBAC patterns
  providers: [PermissionService, RbacGuard],   // Core RBAC services
  exports: [PermissionService, RbacGuard]      // Make available to other modules
})
export class RbacModule {}
