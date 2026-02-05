// Import Global and Module decorators
import { Global, Module } from '@nestjs/common';
// Import AuditService for RBAC action logging
import { AuditService } from './audit.service';

/**
 * AuditModule - Global module providing audit logging functionality
 * Marked as @Global so AuditService is available throughout the application
 * without needing to import AuditModule in every feature module
 */
@Global()
@Module({
  providers: [AuditService],  // Register AuditService as a provider
  exports: [AuditService]      // Export for use in other modules
})
export class AuditModule {}
