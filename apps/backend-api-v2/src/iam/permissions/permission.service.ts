// Import NestJS exception classes
import {
  ConflictException,
  Injectable,
  NotFoundException
} from '@nestjs/common';
// Import Express Request type
import type { Request } from 'express';
// Import PrismaService for database operations
import { PrismaService } from '../../database/prisma.service';
// Import AuditService for logging changes
import { AuditService } from '../../audit/audit.service';

/**
 * AdminPermissionService - Business logic for permission CRUD operations
 * Handles permission management with audit logging and referential integrity checks
 */
@Injectable()
export class AdminPermissionService {
  /**
   * Constructor - injects dependencies
   * @param prisma - Database service
   * @param audit - Audit logging service
   */
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  /**
   * List all non-deleted permissions, ordered by key
   * @returns Array of permission records
   */
  async list(): Promise<any[]> {
    return this.prisma.permission.findMany({
      where: { deletedAt: null },  // Exclude soft-deleted
      orderBy: { key: 'asc' }       // Sort alphabetically
    });
  }

  /**
   * Get a single permission by ID
   * @param id - Permission UUID
   * @returns Permission record
   * @throws NotFoundException if not found or soft-deleted
   */
  async getById(id: string): Promise<any> {
    const row = await this.prisma.permission.findFirst({
      where: { id, deletedAt: null }
    });
    if (!row) throw new NotFoundException('Permission not found');
    return row;
  }

  /**
   * Create a new permission or restore soft-deleted one
   * If permission key exists but is soft-deleted, it will be restored
   * @param params - Permission data and audit context
   * @returns Created/restored permission record
   * @throws ConflictException if key already exists (and is not deleted)
   */
  async create(params: {
    key: string;
    description?: string;
    actorAdminUserId: string;
    request?: Request;
  }): Promise<any> {
    // Check if permission with this key already exists
    const existing = await this.prisma.permission.findUnique({ where: { key: params.key } });

    // If exists and not deleted, throw conflict error
    if (existing && existing.deletedAt === null) {
      throw new ConflictException('Permission key already exists');
    }

    // Either update (restore) existing soft-deleted permission or create new one
    const created = existing
      ? await this.prisma.permission.update({
          where: { id: existing.id },
          data: { key: params.key, description: params.description, deletedAt: null }
        })
      : await this.prisma.permission.create({
          data: { key: params.key, description: params.description }
        });

    // Log creation/restoration to audit log
    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'permission.create',
      targetType: 'permission',
      targetId: created.id,
      before: existing ? { id: existing.id, key: existing.key, deletedAt: existing.deletedAt } : null,
      after: { id: created.id, key: created.key, description: created.description },
      request: params.request
    });

    return created;
  }

  /**
   * Update an existing permission
   * @param params - Permission ID, updated fields, and audit context
   * @returns Updated permission record
   * @throws NotFoundException if permission not found or soft-deleted
   */
  async update(params: {
    id: string;
    key?: string;
    description?: string;
    actorAdminUserId: string;
    request?: Request;
  }): Promise<any> {
    // Get permission before update for audit log
    const before = await this.prisma.permission.findFirst({ where: { id: params.id, deletedAt: null } });
    if (!before) throw new NotFoundException('Permission not found');

    // Update permission with provided fields
    const after = await this.prisma.permission.update({
      where: { id: params.id },
      data: {
        key: params.key ?? undefined,            // Update key if provided
        description: params.description ?? undefined  // Update description if provided
      }
    });

    // Log update to audit log with before/after state
    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'permission.update',
      targetType: 'permission',
      targetId: after.id,
      before: { key: before.key, description: before.description },
      after: { key: after.key, description: after.description },
      request: params.request
    });

    return after;
  }

  /**
   * Soft-delete a permission (sets deletedAt timestamp)
   * Prevents deletion if permission is currently assigned to any role
   * @param params - Permission ID and audit context
   * @throws NotFoundException if permission not found or already deleted
   * @throws ConflictException if permission is assigned to a role
   */
  async softDelete(params: {
    id: string;
    actorAdminUserId: string;
    request?: Request;
  }): Promise<void> {
    // Get permission before deletion for audit log
    const before = await this.prisma.permission.findFirst({ where: { id: params.id, deletedAt: null } });
    if (!before) throw new NotFoundException('Permission not found');

    // Check if permission is assigned to any non-deleted role
    const inUse = await this.prisma.rolePermission.findFirst({
      where: {
        permissionId: params.id,
        role: { deletedAt: null }  // Only check active roles
      },
      select: { roleId: true }
    });
    // Prevent deletion if still in use (referential integrity)
    if (inUse) throw new ConflictException('Permission is assigned to a role');

    // Soft-delete by setting deletedAt timestamp
    await this.prisma.permission.update({
      where: { id: params.id },
      data: { deletedAt: new Date() }
    });

    // Log deletion to audit log
    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'permission.delete',
      targetType: 'permission',
      targetId: params.id,
      before: { key: before.key, description: before.description },
      after: { deleted: true },
      request: params.request
    });
  }
}
