// Import Injectable decorator
import { Injectable } from '@nestjs/common';
// Import Prisma enum for admin user status
import { AdminUserStatus } from '@prisma/client';
// Import PrismaService for database access
import { PrismaService } from '../../database/prisma.service';
// Import permission type definitions
import type { PermissionKey, PermissionResolution } from './permission.types';

/**
 * Remove duplicate items from an array while preserving order
 * @param items - Array with potential duplicates
 * @returns New array with duplicates removed
 */
function uniq<T>(items: readonly T[]): T[] {
  return Array.from(new Set(items));
}

/**
 * Check if a granted permission satisfies a required permission
 * Supports wildcard matching at resource and action levels
 * 
 * Examples:
 *   permissionMatches('user:create', 'user:create') => true (exact match)
 *   permissionMatches('user:create', 'user:*') => true (action wildcard)
 *   permissionMatches('user:create', '*:create') => true (resource wildcard)
 *   permissionMatches('user:create', '*') => true (superuser wildcard)
 * 
 * @param required - Permission key required by the route
 * @param granted - Permission key granted to the user
 * @returns true if granted permission satisfies the requirement
 */
export function permissionMatches(required: PermissionKey, granted: PermissionKey): boolean {
  // Superuser wildcard grants everything
  if (granted === '*') return true;
  
  // A required wildcard is not used by our decorators; treat it as non-match
  if (required === '*') return false;

  // Parse permission format: "resource:action"
  // Segment wildcard support: "resource:*" matches "resource:action"
  const [reqRes, reqAct] = required.split(':');
  const [grRes, grAct] = granted.split(':');

  // Validate permission format (must have both resource and action)
  if (!reqRes || !reqAct || !grRes || !grAct) return false;

  // Check resource match: exact match or granted has wildcard
  const resOk = grRes === '*' || grRes === reqRes;
  // Check action match: exact match or granted has wildcard
  const actOk = grAct === '*' || grAct === reqAct;

  // Both resource and action must match
  return resOk && actOk;
}

/**
 * PermissionService - Service for resolving and checking RBAC permissions
 * Handles permission resolution from database and permission matching logic
 */
@Injectable()
export class PermissionService {
  /**
   * Constructor - injects PrismaService
   * @param prisma - Database service
   */
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Resolve all permissions for an admin user by their Cognito subject ID
   * 
   * Process:
   * 1. Find admin user by Cognito sub (not deleted)
   * 2. Check user is ACTIVE status
   * 3. Get all assigned roles (not deleted)
   * 4. Get all permissions from those roles (not deleted)
   * 5. Return flattened permission set with role names
   * 
   * @param cognitoSub - Cognito user ID from JWT
   * @returns PermissionResolution with user's roles and permissions, or null if not found/inactive
   */
  async resolveForAdminCognitoSub(cognitoSub: string): Promise<PermissionResolution | null> {
    // Look up admin user by Cognito subject
    const admin = await this.prisma.adminUser.findFirst({
      where: {
        cognitoSub,       // Match Cognito user ID
        deletedAt: null   // Exclude soft-deleted users
      },
      select: {
        id: true,
        status: true
      }
    });

    // User not found in database
    if (!admin) return null;
    // User exists but is not active (could be inactive or suspended)
    if (admin.status !== AdminUserStatus.ACTIVE) return null;

    // Get all roles assigned to this admin user
    const roles = await this.prisma.adminUserRole.findMany({
      where: { adminUserId: admin.id },
      select: { role: { select: { id: true, name: true, deletedAt: true } } }
    });

    // Filter out soft-deleted roles and extract names
    const roleNames = roles
      .map((r) => r.role)
      .filter((r) => r.deletedAt === null)
      .map((r) => r.name);

    // Extract role IDs for permission lookup
    const roleIds = roles
      .map((r) => r.role)
      .filter((r) => r.deletedAt === null)
      .map((r) => r.id);

    // If user has no roles, return empty permission set
    if (roleIds.length === 0) {
      return {
        adminUserId: admin.id,
        roleNames: [],
        grantedPermissions: []
      };
    }

    // Get all permissions from the user's roles
    const perms = await this.prisma.rolePermission.findMany({
      where: { roleId: { in: roleIds } },  // Find permissions for these roles
      select: { permission: { select: { key: true, deletedAt: true } } }
    });

    // Filter out soft-deleted permissions, extract keys, and deduplicate
    const grantedPermissions = uniq(
      perms
        .map((p) => p.permission)
        .filter((p) => p.deletedAt === null)
        .map((p) => p.key as PermissionKey)
    );

    // Return complete permission resolution
    return {
      adminUserId: admin.id,
      roleNames: uniq(roleNames),  // Remove duplicate role names
      grantedPermissions
    };
  }

  /**
   * Check if a user's permissions satisfy at least one required permission
   * Uses ANY-OF (OR) semantics: user needs at least one match
   * 
   * @param requiredAnyOf - Array of permissions, user needs at least one
   * @param resolution - User's resolved permissions from database
   * @returns true if user has at least one required permission
   */
  isAllowed(requiredAnyOf: readonly PermissionKey[], resolution: PermissionResolution): boolean {
    // No requirements means deny (fail-safe)
    if (requiredAnyOf.length === 0) return false;

    // Check each required permission
    for (const required of requiredAnyOf) {
      // Check each granted permission
      for (const granted of resolution.grantedPermissions) {
        // If any granted permission matches, user is allowed
        if (permissionMatches(required, granted)) return true;
      }
    }

    // No matches found, deny access
    return false;
  }
}
