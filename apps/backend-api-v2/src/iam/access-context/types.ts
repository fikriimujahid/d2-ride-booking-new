export type ModuleName = string;
export type ModuleAction = string;

/**
 * Generic, permission-driven access map.
 *
 * Example:
 * {
 *   driver: { view: true, read: true, update: false }
 * }
 */
export type ModuleAccessMap = Record<ModuleName, Record<ModuleAction, boolean>>;

export interface AdminAccessContextUser {
  /** Database UUID (needed by admin UI for display/debug only). */
  id: string;
  email: string;
  name: string;
}

export interface AdminAccessContext {
  user: AdminAccessContextUser;
  roles: readonly string[];
  permissions: readonly string[];
  modules: ModuleAccessMap;
}
