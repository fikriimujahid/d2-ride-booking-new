// Import ModuleAccessMap type for building authorization snapshot
import type { ModuleAccessMap } from './types';
// Import PermissionKey type from RBAC module
import type { PermissionKey } from '../rbac/permission.types';
// Import permission matching function for wildcard support
import { permissionMatches } from '../rbac/permission.service';

/**
 * ParsedPermission - Decomposed permission key
 * Breaks 'module:action' format into components for processing
 */
export interface ParsedPermission {
  /** Module name (e.g., 'driver', 'role', 'admin-user') */
  module: string;
  /** Action within module (e.g., 'view', 'create', 'update', 'delete') */
  action: string;
}

/**
 * Parses a permission key in the standard form: <module>:<action>
 * Validates format and returns structured representation.
 * 
 * Returns null for malformed inputs:
 * - Empty strings
 * - Missing colon
 * - Multiple colons
 * - Empty module or action
 * 
 * @param value - Permission key string (e.g., 'driver:create')
 * @returns Parsed components or null if invalid
 */
export function parsePermissionKey(value: string): ParsedPermission | null {
  // Trim whitespace from input
  const raw = value.trim();
  // Reject empty strings
  if (raw.length === 0) return null;

  // Find first colon separator
  const firstColon = raw.indexOf(':');
  // Colon must exist and not be at start
  if (firstColon <= 0) return null;
  // Colon cannot be the last character
  if (firstColon === raw.length - 1) return null;

  // Only one ':' is allowed (no 'module:submodule:action')
  if (raw.indexOf(':', firstColon + 1) !== -1) return null;

  // Extract module and action parts
  const module = raw.slice(0, firstColon).trim();
  const action = raw.slice(firstColon + 1).trim();
  // Both parts must be non-empty after trimming
  if (module.length === 0 || action.length === 0) return null;

  return { module, action };
}

// Constant for the visibility action that gates module access in UI
const VISIBILITY_ACTION = 'view';

/**
 * Adds an action to a module's action set in the map
 * Creates new set if module doesn't exist yet
 * 
 * @param map - Map of module names to their action sets
 * @param module - Module name to add action to
 * @param action - Action to add to module's set
 */
function addToMapSet(map: Map<string, Set<string>>, module: string, action: string): void {
  // Check if module already has actions
  const existing = map.get(module);
  if (existing) {
    // Add to existing set
    existing.add(action);
    return;
  }
  // Create new set with this action
  map.set(module, new Set([action]));
}

/**
 * Sorts an iterable by a string representation
 * Used for deterministic ordering in API responses
 * 
 * @param values - Iterable to sort
 * @param toString - Function to convert value to sortable string
 * @returns Sorted array
 */
function sortedKeys<T>(values: Iterable<T>, toString: (v: T) => string): T[] {
  return Array.from(values).sort((a, b) => toString(a).localeCompare(toString(b)));
}

/**
 * Builds the authorization snapshot used by the admin UI.
 * Converts database permissions into a structured map for frontend consumption.
 * 
 * Process:
 * 1. Parse all known permissions from catalog to establish universe of modules/actions
 * 2. Ensure 'view' action exists for every module (UI visibility gate)
 * 3. Include any granted permissions not in catalog (defensive)
 * 4. Check each action against granted permissions using wildcard matching
 * 5. Return sorted, deterministic map for consistent API responses
 * 
 * - `allPermissionKeys` defines the universe of known module/action pairs (typically from DB Permission table)
 * - `grantedPermissionKeys` are the user's effective permissions (flattened from DB role assignments)
 * - Missing permissions default to false
 * - For every module present in the universe, `view` is always present in the output (default false)
 * 
 * @param options.allPermissionKeys - Complete catalog of permissions from database
 * @param options.grantedPermissionKeys - User's effective permissions (may include wildcards like '*' or 'driver:*')
 * @returns Nested map of module → action → boolean for UI authorization
 */
export function buildModuleAccessMap(options: {
  allPermissionKeys: readonly string[];
  grantedPermissionKeys: readonly string[];
}): ModuleAccessMap {
  // Build universe of all known modules and their actions
  const universe = new Map<string, Set<string>>();

  // Parse catalog to establish available modules/actions
  for (const key of options.allPermissionKeys) {
    const parsed = parsePermissionKey(key);
    // Skip malformed keys
    if (!parsed) continue;
    // Add action to module's set
    addToMapSet(universe, parsed.module, parsed.action);
  }

  // Ensure visibility action exists for any module that exists at all.
  // The 'view' action gates whether the module appears in UI navigation.
  for (const [module, actions] of universe.entries()) {
    if (!actions.has(VISIBILITY_ACTION)) actions.add(VISIBILITY_ACTION);
  }

  // Include actions that are granted but missing from the universe (defensive).
  // Handles edge case where permission is assigned but not in catalog.
  for (const key of options.grantedPermissionKeys) {
    const parsed = parsePermissionKey(key);
    // Skip malformed and wildcard-only keys
    if (!parsed) continue;
    // Add to universe if not present
    addToMapSet(universe, parsed.module, parsed.action);
    // Ensure view action exists for this module
    const actions = universe.get(parsed.module);
    if (actions && !actions.has(VISIBILITY_ACTION)) actions.add(VISIBILITY_ACTION);
  }

  // Filter and validate granted permission keys
  // Keep raw keys (including wildcard '*' and 'module:*') for matching
  const grantedKeys: PermissionKey[] = options.grantedPermissionKeys
    .map((k) => k.trim())
    .filter((k): k is PermissionKey => k === '*' || parsePermissionKey(k) !== null);

  /**
   * Checks if a specific module:action is granted by the user's permissions
   * Supports wildcard matching: '*' grants everything, 'driver:*' grants all driver actions
   * 
   * @param module - Module to check
   * @param action - Action to check
   * @returns true if user has permission (directly or via wildcard)
   */
  function isGranted(module: string, action: string): boolean {
    // Construct the required permission key
    const required = `${module}:${action}` as PermissionKey;
    // Check if any granted permission matches (handles wildcards)
    for (const granted of grantedKeys) {
      if (permissionMatches(required, granted)) return true;
    }
    return false;
  }

  // Build final result object with sorted keys for deterministic output
  const result: ModuleAccessMap = {};
  // Sort modules alphabetically
  const modulesSorted = sortedKeys(universe.keys(), (s) => s);

  // Process each module
  for (const module of modulesSorted) {
    const actions = universe.get(module);
    // Skip empty modules (shouldn't happen)
    if (!actions || actions.size === 0) continue;

    // Sort actions alphabetically
    const actionsSorted = sortedKeys(actions, (s) => s);
    // Build action map for this module
    const moduleMap: Record<string, boolean> = {};

    // Check each action against granted permissions
    for (const action of actionsSorted) {
      moduleMap[action] = isGranted(module, action);
    }

    // Final guarantee: view action must exist in output
    if (!(VISIBILITY_ACTION in moduleMap)) {
      moduleMap[VISIBILITY_ACTION] = isGranted(module, VISIBILITY_ACTION);
    }

    // Add module to result
    result[module] = moduleMap;
  }

  return result;
}
