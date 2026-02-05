// Import NestJS exception classes
import { ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
// Import AdminUserStatus enum from Prisma
import { AdminUserStatus } from '@prisma/client';
// Import AuthenticatedUser interface from auth module
import type { AuthenticatedUser } from '../../auth/interfaces/authenticated-user';
// Import Prisma service for database operations
import { PrismaService } from '../../database/prisma.service';
// Import permission parser utilities
import { buildModuleAccessMap, parsePermissionKey } from './permission.parser';
// Import access context types
import type { AdminAccessContext } from './types';

/**
 * Type guard to check if value is a non-empty string
 * @param value - Value to check
 * @returns true if value is string with content after trimming
 */
function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

/**
 * Extracts display name from Cognito JWT claims
 * Tries multiple claim fields in priority order:
 * 1. 'name' claim (full name)
 * 2. 'given_name' + 'family_name' (first + last)
 * 3. 'given_name' only (first name)
 * 4. Email as fallback
 * 
 * @param user - Authenticated user with JWT claims
 * @returns Display name for UI
 */
function getDisplayName(user: AuthenticatedUser): string {
  // Cast claims to record for property access
  const claims = user.claims as Record<string, unknown>;

  // Try 'name' claim first (e.g., "John Doe")
  const name = claims.name;
  if (isNonEmptyString(name)) return name.trim();

  // Try combining given_name and family_name
  const given = claims.given_name;
  const family = claims.family_name;
  if (isNonEmptyString(given) && isNonEmptyString(family)) return `${given.trim()} ${family.trim()}`;
  // Use given_name alone if available
  if (isNonEmptyString(given)) return given.trim();

  // Fallback to email address
  return user.email;
}

/**
 * Sort and deduplicate string array
 * Used for consistent ordering in API responses
 * @param values - Array of strings
 * @returns Sorted array with duplicates removed
 */
function uniqueSorted(values: readonly string[]): string[] {
  return Array.from(new Set(values)).sort((a, b) => a.localeCompare(b));
}

/**
 * AccessContextService - Business logic for admin access context
 * Builds authorization snapshot for admin UI bootstrap.
 * Called on login/refresh to provide frontend with complete permission state.
 */
@Injectable()
export class AccessContextService {
  /**
   * Constructor - injects dependencies
   * @param prisma - Database service
   */
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Get complete admin access context for authenticated user
   * Returns user identity, assigned roles, effective permissions, and UI module map.
   * 
   * Flow:
   * 1. Verify user authenticated
   * 2. Look up admin_user record by cognitoSub
   * 3. Verify admin is ACTIVE (not DISABLED/PENDING)
   * 4. Load assigned roles
   * 5. Resolve effective permissions from roles
   * 6. Build module access map for UI
   * 7. Return complete snapshot
   * 
   * @param authUser - Authenticated user from JwtAuthGuard
   * @returns Complete access context for admin UI
   * @throws UnauthorizedException if not authenticated
   * @throws ForbiddenException if admin user not found or not ACTIVE
   */
  async getAdminMe(authUser: AuthenticatedUser): Promise<AdminAccessContext> {
    // Verify authentication
    if (!authUser?.userId) throw new UnauthorizedException('Unauthorized');

    // Look up admin user by Cognito sub (unique identifier)
    const admin = await this.prisma.adminUser.findFirst({
      where: {
        cognitoSub: authUser.userId,
        deletedAt: null,
        status: AdminUserStatus.ACTIVE
      },
      select: { id: true, email: true }
    });

    if (!admin) {
      // Authenticated as ADMIN group, but not provisioned for admin RBAC.
      // User exists in Cognito but not in admin_user table, or status is not ACTIVE.
      throw new ForbiddenException('Forbidden');
    }

    // Load role assignments for this admin user
    const assignments = await this.prisma.adminUserRole.findMany({
      where: {
        adminUserId: admin.id,
        role: { deletedAt: null }  // Only include active roles
      },
      select: {
        role: { select: { id: true, name: true } }
      }
    });

    // Extract role names for display (sorted, deduplicated)
    const roleNames = uniqueSorted(assignments.map((x) => x.role.name));

    // Extract role IDs for permission resolution
    const roleIds = uniqueSorted(assignments.map((x) => x.role.id));

    // Resolve effective permissions from DB role assignments (no role-name logic).
    let grantedPermissionKeys: string[] = [];
    if (roleIds.length > 0) {
      // Query all permissions assigned to user's roles
      const rows = await this.prisma.rolePermission.findMany({
        where: {
          roleId: { in: roleIds },
          permission: { deletedAt: null }  // Only include active permissions
        },
        select: {
          permission: { select: { key: true } }
        }
      });

      // Keep raw keys (including wildcard '*') so the UI snapshot matches RBAC enforcement.
      grantedPermissionKeys = uniqueSorted(rows.map((r) => r.permission.key));
    }

    // Universe of modules/actions comes from DB permission catalog.
    // This defines all possible permissions in the system.
    const catalog = await this.prisma.permission.findMany({
      where: { deletedAt: null },
      select: { key: true }
    });

    // Extract all permission keys from catalog
    const allPermissionKeys = catalog.map((p) => p.key);
    // Build module access map for UI authorization
    const modules = buildModuleAccessMap({
      allPermissionKeys,
      grantedPermissionKeys
    });

    // Return complete access context
    return {
      user: {
        id: admin.id,
        email: admin.email,
        name: getDisplayName(authUser)
      },
      roles: roleNames,
      permissions: grantedPermissionKeys,
      modules
    };
  }
}
