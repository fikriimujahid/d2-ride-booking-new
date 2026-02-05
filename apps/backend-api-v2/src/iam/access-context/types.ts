// Type alias for module name (e.g., 'driver', 'admin-user', 'role')
export type ModuleName = string;
// Type alias for action within a module (e.g., 'view', 'create', 'update')
export type ModuleAction = string;

/**
 * Generic, permission-driven access map.
 * Maps module names to action-permission pairs for UI authorization.
 * 
 * Example:
 * {
 *   driver: { view: true, read: true, update: false },
 *   role: { view: true, create: true, delete: false }
 * }
 * 
 * Used by admin frontend to:
 * - Show/hide menu items (view action)
 * - Enable/disable buttons (create, update, delete actions)
 * - Control feature visibility
 */
export type ModuleAccessMap = Record<ModuleName, Record<ModuleAction, boolean>>;

/**
 * AdminAccessContextUser - Minimal user info for UI display
 * Contains identity information from Cognito and database
 */
export interface AdminAccessContextUser {
  /** Database UUID (needed by admin UI for display/debug only). */
  id: string;
  /** Email address from admin_user table */
  email: string;
  /** Display name from Cognito JWT claims (name, given_name, or email fallback) */
  name: string;
}

/**
 * AdminAccessContext - Complete authorization snapshot for admin UI bootstrap
 * Returned by /admin/me endpoint on login/refresh.
 * Contains everything the frontend needs to determine UI state.
 */
export interface AdminAccessContext {
  /** Admin user identity information */
  user: AdminAccessContextUser;
  /** List of role names assigned to this admin (sorted) */
  roles: readonly string[];
  /** List of effective permission keys (flattened from roles, includes wildcards) */
  permissions: readonly string[];
  /** Per-module action authorization map for UI visibility control */
  modules: ModuleAccessMap;
}
