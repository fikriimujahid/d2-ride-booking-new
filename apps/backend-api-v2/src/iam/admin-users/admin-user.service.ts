// Import NestJS exception classes
import {
  ConflictException,
  Injectable,
  NotFoundException
} from '@nestjs/common';
// Import AdminUserStatus enum from Prisma
import { AdminUserStatus } from '@prisma/client';
// Import Express Request type
import type { Request } from 'express';
// Import audit service for logging changes
import { AuditService } from '../../audit/audit.service';
// Import Prisma service for database operations
import { PrismaService } from '../../database/prisma.service';

/**
 * Sort and deduplicate string array
 * Used for consistent ordering in API responses and audit logs
 * @param values - Array of strings
 * @returns Sorted array with duplicates removed
 */
function uniqueSorted(values: readonly string[]): string[] {
  return Array.from(new Set(values)).sort((a, b) => a.localeCompare(b));
}

/**
 * AdminUserService - Business logic for admin user CRUD operations
 * Manages admin_user records that link Cognito users to RBAC system.
 * Handles user creation, updates, deletion, and role assignment.
 * All operations include audit logging.
 */
@Injectable()
export class AdminUserService {
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
   * List all active admin users
   * Returns users with their assigned roles.
   * Sorted by creation date (newest first).
   * 
   * @returns Array of admin users with roles
   */
  async list() {
    return this.prisma.adminUser.findMany({
      where: { deletedAt: null },  // Only active users
      orderBy: { createdAt: 'desc' },  // Newest first
      include: {
        roles: {
          where: { role: { deletedAt: null } },  // Only active roles
          select: { roleId: true, role: { select: { id: true, name: true } } }
        }
      }
    });
  }

  /**
   * Get single admin user by ID
   * Returns user with assigned roles.
   * 
   * @param id - Admin user UUID
   * @returns Admin user with roles
   * @throws NotFoundException if user not found or deleted
   */
  async getById(id: string) {
    const admin = await this.prisma.adminUser.findFirst({
      where: { id, deletedAt: null },  // Only active user
      include: {
        roles: {
          where: { role: { deletedAt: null } },  // Only active roles
          select: { roleId: true, role: { select: { id: true, name: true } } }
        }
      }
    });
    if (!admin) throw new NotFoundException('Admin user not found');
    return admin;
  }

  /**
   * Create new admin user
   * Links Cognito user to RBAC system.
   * If admin user was soft-deleted, restores it instead of creating new.
   * Logs audit trail of creation or restoration.
   * 
   * @param params.cognitoSub - Cognito user UUID (unique identifier)
   * @param params.email - Email address
   * @param params.status - Initial status (defaults to ACTIVE)
   * @param params.actorAdminUserId - ID of admin performing action (for audit)
   * @param params.request - HTTP request (for audit metadata)
   * @returns Created or restored admin user
   * @throws ConflictException if admin user already exists and is active
   */
  async create(params: {
    cognitoSub: string;
    email: string;
    status?: AdminUserStatus;
    actorAdminUserId: string;
    request?: Request;
  }) {
    // Check if admin user already exists (including soft-deleted)
    const existing = await this.prisma.adminUser.findUnique({ where: { cognitoSub: params.cognitoSub } });
    if (existing && existing.deletedAt === null) {
      // Active admin user already exists for this Cognito sub
      throw new ConflictException('Admin user already exists for this Cognito sub');
    }

    // Either restore soft-deleted user or create new one
    const created = existing
      ? await this.prisma.adminUser.update({
          where: { id: existing.id },
          data: {
            email: params.email,
            status: params.status ?? AdminUserStatus.ACTIVE,
            deletedAt: null  // Restore by clearing deletedAt
          }
        })
      : await this.prisma.adminUser.create({
          data: {
            cognitoSub: params.cognitoSub,
            email: params.email,
            status: params.status ?? AdminUserStatus.ACTIVE
          }
        });

    // Log audit trail (creation or restoration)
    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'admin.create',
      targetType: 'admin_user',
      targetId: created.id,
      before: existing ? { id: existing.id, deletedAt: existing.deletedAt } : null,
      after: { cognitoSub: created.cognitoSub, email: created.email, status: created.status },
      request: params.request
    });

    return created;
  }

  /**
   * Update admin user
   * Updates email or status of admin user.
   * Logs audit trail with before and after state.
   * 
   * @param params.id - Admin user UUID
   * @param params.email - New email (optional)
   * @param params.status - New status (optional)
   * @param params.actorAdminUserId - ID of admin performing action (for audit)
   * @param params.request - HTTP request (for audit metadata)
   * @returns Updated admin user
   * @throws NotFoundException if admin user not found or deleted
   */
  async update(params: {
    id: string;
    email?: string;
    status?: AdminUserStatus;
    actorAdminUserId: string;
    request?: Request;
  }) {
    // Get current state for audit trail
    const before = await this.prisma.adminUser.findFirst({ where: { id: params.id, deletedAt: null } });
    if (!before) throw new NotFoundException('Admin user not found');

    // Update with provided fields (undefined fields are ignored)
    const after = await this.prisma.adminUser.update({
      where: { id: params.id },
      data: {
        email: params.email ?? undefined,
        status: params.status ?? undefined
      }
    });

    // Log audit trail with before/after comparison
    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'admin.update',
      targetType: 'admin_user',
      targetId: after.id,
      before: { email: before.email, status: before.status },
      after: { email: after.email, status: after.status },
      request: params.request
    });

    return after;
  }

  /**
   * Soft delete admin user
   * Sets deletedAt timestamp instead of removing record.
   * User can be restored via create endpoint with same cognitoSub.
   * Logs audit trail of deletion.
   * 
   * @param params.id - Admin user UUID
   * @param params.actorAdminUserId - ID of admin performing action (for audit)
   * @param params.request - HTTP request (for audit metadata)
   * @throws NotFoundException if admin user not found or already deleted
   */
  async softDelete(params: { id: string; actorAdminUserId: string; request?: Request }) {
    // Verify user exists and is not already deleted
    const before = await this.prisma.adminUser.findFirst({ where: { id: params.id, deletedAt: null } });
    if (!before) throw new NotFoundException('Admin user not found');

    // Set deletedAt timestamp (soft delete)
    await this.prisma.adminUser.update({
      where: { id: params.id },
      data: { deletedAt: new Date() }
    });

    // Log audit trail
    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'admin.delete',
      targetType: 'admin_user',
      targetId: params.id,
      before: { email: before.email, status: before.status },
      after: { deleted: true },
      request: params.request
    });
  }

  /**
   * Replace admin user's roles (not additive)
   * Removes all existing role assignments and assigns new ones.
   * Empty array removes all roles.
   * Validates that all role IDs exist and are active.
   * Logs audit trail with before/after role IDs.
   * 
   * Process:
   * 1. Verify admin user exists
   * 2. Deduplicate and sort requested role IDs
   * 3. Get current role assignments for audit trail
   * 4. Validate all requested roles exist and are active
   * 5. Delete all existing assignments in transaction
   * 6. Create new assignments in same transaction
   * 7. Log audit trail
   * 
   * @param params.adminUserId - Admin user UUID
   * @param params.roleIds - Array of role UUIDs to assign
   * @param params.actorAdminUserId - ID of admin performing action (for audit)
   * @param params.request - HTTP request (for audit metadata)
   * @throws NotFoundException if admin user not found or any role not found
   */
  async replaceRoles(params: {
    adminUserId: string;
    roleIds: readonly string[];
    actorAdminUserId: string;
    request?: Request;
  }) {
    // Verify admin user exists
    const admin = await this.prisma.adminUser.findFirst({ where: { id: params.adminUserId, deletedAt: null } });
    if (!admin) throw new NotFoundException('Admin user not found');

    // Deduplicate and sort requested role IDs
    const desired = uniqueSorted(params.roleIds);

    // Get current role assignments for audit trail
    const existing = await this.prisma.adminUserRole.findMany({
      where: { adminUserId: params.adminUserId },
      select: { roleId: true }
    });
    const beforeRoleIds = uniqueSorted(existing.map((x) => x.roleId));

    // Validate all requested roles exist and are active
    if (desired.length > 0) {
      const found = await this.prisma.role.findMany({
        where: { id: { in: desired }, deletedAt: null },
        select: { id: true }
      });
      if (found.length !== desired.length) throw new NotFoundException('One or more roles not found');
    }

    // Replace role assignments in transaction (atomic operation)
    await this.prisma.$transaction(async (tx: any) => {
      // Delete all existing assignments
      await tx.adminUserRole.deleteMany({ where: { adminUserId: params.adminUserId } });
      // Create new assignments if any
      if (desired.length > 0) {
        await tx.adminUserRole.createMany({
          data: desired.map((roleId) => ({ adminUserId: params.adminUserId, roleId })),
          skipDuplicates: true  // Prevent errors if duplicate somehow exists
        });
      }
    });

    // Log audit trail with before/after role arrays
    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'role.assign',
      targetType: 'admin_user',
      targetId: params.adminUserId,
      before: { roleIds: beforeRoleIds },
      after: { roleIds: desired },
      request: params.request
    });
  }
}
