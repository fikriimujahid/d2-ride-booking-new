// Import Injectable decorator
import { Injectable } from '@nestjs/common';
// Import PrismaService for database access
import { PrismaService } from '../../database/prisma.service';

/**
 * PermissionsService - Lower-level service for permission database operations
 * Used for seeding and bulk operations
 * For CRUD API operations, see AdminPermissionService
 */
@Injectable()
export class PermissionsService {
  /**
   * Constructor - injects PrismaService
   * @param prisma - Database service
   */
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Upsert a permission - create if doesn't exist, update if soft-deleted
   * Used during database seeding to ensure permissions exist
   * @param params - Permission key and optional description
   * @returns Created or updated permission record
   */
  async upsertPermission(params: { key: string; description?: string }) {
    return this.prisma.permission.upsert({
      where: { key: params.key },  // Find by unique key
      update: { description: params.description, deletedAt: null },  // Restore if soft-deleted
      create: { key: params.key, description: params.description }   // Create if not exists
    });
  }
}
