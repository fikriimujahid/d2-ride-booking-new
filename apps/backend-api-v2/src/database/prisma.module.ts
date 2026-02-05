// Import Global and Module decorators
import { Global, Module } from '@nestjs/common';
// Import PrismaService for database access
import { PrismaService } from './prisma.service';

/**
 * PrismaModule - Global module providing database access via Prisma ORM
 * Marked as @Global so PrismaService is available throughout the application
 * without needing to import PrismaModule in every feature module
 */
@Global()
@Module({
  providers: [PrismaService],  // Register PrismaService as a provider
  exports: [PrismaService]      // Export for injection in other modules
})
export class PrismaModule {}
