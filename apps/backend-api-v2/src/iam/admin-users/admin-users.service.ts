// Import NestJS exception classes
import { ForbiddenException, Injectable } from '@nestjs/common';
// Import AdminUserStatus enum from Prisma
import { AdminUserStatus } from '@prisma/client';
// Import Express Request type
import type { Request } from 'express';
// Import audit service for logging changes
import { AuditService } from '../../audit/audit.service';
// Import Prisma service for database operations
import { PrismaService } from '../../database/prisma.service';

/**
 * AdminUsersService - Helper service for admin user operations
 * Provides utility methods for admin user management used internally.
 * Complements AdminUserService with specialized operations:
 * - ensureAdminUser: Upsert operation for JIT provisioning
 * - setAdminStatus: Status changes
 * - assignRole/unassignRole: Individual role operations
 * 
 * Used by internal services, not exposed via REST API directly.
 */
@Injectable()
export class AdminUsersService {
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
   * Ensure admin user exists (upsert operation)
   * Creates admin user if doesn't exist, updates email if exists.
   * Used for just-in-time (JIT) provisioning during authentication.
   * Automatically restores soft-deleted users.
   * Logs audit trail only for new users.
   * 
   * @param params.cognitoSub - Cognito user UUID (unique identifier)
   * @param params.email - Email address
   * @param params.actorAdminUserId - ID of admin performing action (for audit)
   * @param params.request - HTTP request (for audit metadata)
   * @returns Admin user (created or updated)
   */
  async ensureAdminUser(params: {
    cognitoSub: string;
    email: string;
    actorAdminUserId: string;
    request?: Request;
  }) {
    // Check if user existed before upsert
    const existing = await this.prisma.adminUser.findUnique({
      where: { cognitoSub: params.cognitoSub }
    });

    // Upsert: update if exists, create if not
    const admin = await this.prisma.adminUser.upsert({
      where: { cognitoSub: params.cognitoSub },
      update: { email: params.email, deletedAt: null },  // Update email, restore if deleted
      create: {
        cognitoSub: params.cognitoSub,
        email: params.email,
        status: AdminUserStatus.ACTIVE
      }
    });

    // Log audit trail only for new users (not updates)
    if (!existing) {
      await this.audit.logRbacAction({
        actorAdminUserId: params.actorAdminUserId,
        action: 'admin.create',
        targetType: 'admin_user',
        targetId: admin.id,
        before: null,
        after: { cognitoSub: admin.cognitoSub, email: admin.email, status: admin.status },
        request: params.request
      });
    }

    return admin;
  }

  /**
   * Set admin user status
   * Changes status between ACTIVE, DISABLED, PENDING.
   * Logs audit trail with before/after status.
   * 
   * @param params.adminUserId - Admin user UUID
   * @param params.status - New status to set
   * @param params.actorAdminUserId - ID of admin performing action (for audit)
   * @param params.request - HTTP request (for audit metadata)
   * @returns Updated admin user
   * @throws ForbiddenException if user not found or deleted
   */
  async setAdminStatus(params: {
    adminUserId: string;
    status: AdminUserStatus;
    actorAdminUserId: string;
    request?: Request;
  }) {
    // Get current state for audit trail
    const before = await this.prisma.adminUser.findUnique({ where: { id: params.adminUserId } });
    if (!before || before.deletedAt) throw new ForbiddenException('Forbidden');

    // Update status
    const after = await this.prisma.adminUser.update({
      where: { id: params.adminUserId },
      data: { status: params.status }
    });

    // Log audit trail with status change
    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'admin.status_change',
      targetType: 'admin_user',
      targetId: after.id,
      before: { status: before.status },
      after: { status: after.status },
      request: params.request
    });

    return after;
  }

  /**
   * Assign single role to admin user
   * Adds role assignment if doesn't exist (idempotent).
   * Logs audit trail of assignment.
   * 
   * Note: For replacing all roles, use AdminUserService.replaceRoles instead.
   * 
   * @param params.adminUserId - Admin user UUID
   * @param params.roleId - Role UUID to assign
   * @param params.actorAdminUserId - ID of admin performing action (for audit)
   * @param params.request - HTTP request (for audit metadata)
   * @returns Created or existing role assignment
   */
  async assignRole(params: {
    adminUserId: string;
    roleId: string;
    actorAdminUserId: string;
    request?: Request;
  }) {
    // Upsert: create if doesn't exist, return existing if does
    const mapping = await this.prisma.adminUserRole.upsert({
      where: { adminUserId_roleId: { adminUserId: params.adminUserId, roleId: params.roleId } },
      update: {},  // No-op if exists
      create: { adminUserId: params.adminUserId, roleId: params.roleId }
    });

    // Log audit trail
    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'role.assign',
      targetType: 'admin_user',
      targetId: params.adminUserId,
      before: null,
      after: { roleId: params.roleId },
      request: params.request
    });

    return mapping;
  }

  /**
   * Unassign single role from admin user
   * Removes role assignment.
   * Logs audit trail of removal.
   * 
   * Note: For replacing all roles, use AdminUserService.replaceRoles instead.
   * 
   * @param params.adminUserId - Admin user UUID
   * @param params.roleId - Role UUID to remove
   * @param params.actorAdminUserId - ID of admin performing action (for audit)
   * @param params.request - HTTP request (for audit metadata)
   */
  async unassignRole(params: {
    adminUserId: string;
    roleId: string;
    actorAdminUserId: string;
    request?: Request;
  }) {
    // Delete the specific role assignment
    await this.prisma.adminUserRole.delete({
      where: { adminUserId_roleId: { adminUserId: params.adminUserId, roleId: params.roleId } }
    });

    // Log audit trail
    await this.audit.logRbacAction({
      actorAdminUserId: params.actorAdminUserId,
      action: 'role.unassign',
      targetType: 'admin_user',
      targetId: params.adminUserId,
      before: null,
      after: { roleId: params.roleId },
      request: params.request
    });
  }
}
