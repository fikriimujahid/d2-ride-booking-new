// Import NestJS Injectable decorator
import { Injectable } from '@nestjs/common';
// Import Express Request type
import type { Request } from 'express';
// Import Prisma JSON types for storing arbitrary data
import { Prisma } from '@prisma/client';
// Import PrismaService for database operations
import { PrismaService } from '../database/prisma.service';

/**
 * RbacAuditAction - Union type of all possible RBAC audit actions
 * Tracks all administrative operations for compliance and security
 */
export type RbacAuditAction =
  | 'admin.create'          // Create new admin user
  | 'admin.status_change'   // Change admin user active/inactive status
  | 'admin.update'          // Update admin user information
  | 'admin.delete'          // Delete admin user
  | 'role.create'           // Create new role
  | 'role.update'           // Update role information
  | 'role.delete'           // Delete role
  | 'role.assign'           // Assign role to user
  | 'role.unassign'         // Remove role from user
  | 'permission.create'     // Create new permission
  | 'permission.update'     // Update permission information
  | 'permission.delete'     // Delete permission
  | 'permission.assign'     // Assign permission to role
  | 'permission.unassign'   // Remove permission from role
  | 'rbac.seed';            // Initial RBAC database seeding

/**
 * AuditService - Service for logging RBAC administrative actions
 * Provides compliance tracking and security audit trail
 * All administrative changes are logged with before/after states
 */
@Injectable()
export class AuditService {
  /**
   * Constructor - injects PrismaService for database access
   * @param prisma - PrismaService instance
   */
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Log an RBAC administrative action to the audit log
   * Captures who did what, when, and from where
   * 
   * @param params - Audit log parameters
   * @param params.actorAdminUserId - ID of admin user performing the action
   * @param params.action - Type of action being performed
   * @param params.targetType - Type of entity being modified (e.g., 'AdminUser', 'Role')
   * @param params.targetId - ID of the entity being modified (optional)
   * @param params.before - State before the change (optional, for updates/deletes)
   * @param params.after - State after the change (optional, for creates/updates)
   * @param params.request - Express request object for IP/user-agent (optional)
   * @returns Promise that resolves when audit log is written
   */
  async logRbacAction(params: {
    actorAdminUserId: string;
    action: RbacAuditAction;
    targetType: string;
    targetId?: string;
    before?: unknown;
    after?: unknown;
    request?: Request;
  }): Promise<void> {
    const { actorAdminUserId, action, targetType, targetId, before, after, request } = params;

    // Convert before/after to Prisma JSON format (handle null vs undefined)
    const beforeJson =
      before === undefined ? undefined : before === null ? Prisma.JsonNull : (before as Prisma.InputJsonValue);
    const afterJson =
      after === undefined ? undefined : after === null ? Prisma.JsonNull : (after as Prisma.InputJsonValue);

    // Create audit log record in database
    await this.prisma.adminAuditLog.create({
      data: {
        actorAdminUserId,                    // Who performed the action
        action,                              // What action was performed
        targetType,                          // Type of resource affected
        targetId,                            // Specific resource ID
        before: beforeJson,                  // State before change (JSON)
        after: afterJson,                    // State after change (JSON)
        ipAddress: request?.ip,              // Client IP address for security
        userAgent: typeof request?.headers?.['user-agent'] === 'string' ? request.headers['user-agent'] : undefined,  // Browser/client info
        requestId: request?.requestId        // Request correlation ID for tracing
      }
    });
  }
}
