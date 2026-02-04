import type { ModuleAccessMap } from './types';
import type { PermissionKey } from '../rbac/permission.types';
import { permissionMatches } from '../rbac/permission.service';

export interface ParsedPermission {
  module: string;
  action: string;
}

/**
 * Parses a permission key in the standard form: <module>:<action>
 * Returns null for malformed inputs.
 */
export function parsePermissionKey(value: string): ParsedPermission | null {
  const raw = value.trim();
  if (raw.length === 0) return null;

  const firstColon = raw.indexOf(':');
  if (firstColon <= 0) return null;
  if (firstColon === raw.length - 1) return null;

  // Only one ':' is allowed.
  if (raw.indexOf(':', firstColon + 1) !== -1) return null;

  const module = raw.slice(0, firstColon).trim();
  const action = raw.slice(firstColon + 1).trim();
  if (module.length === 0 || action.length === 0) return null;

  return { module, action };
}

const VISIBILITY_ACTION = 'view';

function addToMapSet(map: Map<string, Set<string>>, module: string, action: string): void {
  const existing = map.get(module);
  if (existing) {
    existing.add(action);
    return;
  }
  map.set(module, new Set([action]));
}

function sortedKeys<T>(values: Iterable<T>, toString: (v: T) => string): T[] {
  return Array.from(values).sort((a, b) => toString(a).localeCompare(toString(b)));
}

/**
 * Builds the authorization snapshot used by the admin UI.
 *
 * - `allPermissionKeys` defines the universe of known module/action pairs (typically from DB Permission table)
 * - `grantedPermissionKeys` are the user's effective permissions (flattened from DB role assignments)
 * - Missing permissions default to false
 * - For every module present in the universe, `view` is always present in the output (default false)
 */
export function buildModuleAccessMap(options: {
  allPermissionKeys: readonly string[];
  grantedPermissionKeys: readonly string[];
}): ModuleAccessMap {
  const universe = new Map<string, Set<string>>();

  for (const key of options.allPermissionKeys) {
    const parsed = parsePermissionKey(key);
    if (!parsed) continue;
    addToMapSet(universe, parsed.module, parsed.action);
  }

  // Ensure visibility action exists for any module that exists at all.
  for (const [module, actions] of universe.entries()) {
    if (!actions.has(VISIBILITY_ACTION)) actions.add(VISIBILITY_ACTION);
  }

  // Include actions that are granted but missing from the universe (defensive).
  for (const key of options.grantedPermissionKeys) {
    const parsed = parsePermissionKey(key);
    if (!parsed) continue;
    addToMapSet(universe, parsed.module, parsed.action);
    const actions = universe.get(parsed.module);
    if (actions && !actions.has(VISIBILITY_ACTION)) actions.add(VISIBILITY_ACTION);
  }

  const grantedKeys: PermissionKey[] = options.grantedPermissionKeys
    .map((k) => k.trim())
    .filter((k): k is PermissionKey => k === '*' || parsePermissionKey(k) !== null);

  function isGranted(module: string, action: string): boolean {
    const required = `${module}:${action}` as PermissionKey;
    for (const granted of grantedKeys) {
      if (permissionMatches(required, granted)) return true;
    }
    return false;
  }

  const result: ModuleAccessMap = {};
  const modulesSorted = sortedKeys(universe.keys(), (s) => s);

  for (const module of modulesSorted) {
    const actions = universe.get(module);
    if (!actions || actions.size === 0) continue;

    const actionsSorted = sortedKeys(actions, (s) => s);
    const moduleMap: Record<string, boolean> = {};

    for (const action of actionsSorted) {
      moduleMap[action] = isGranted(module, action);
    }

    // Final guarantee.
    if (!(VISIBILITY_ACTION in moduleMap)) {
      moduleMap[VISIBILITY_ACTION] = isGranted(module, VISIBILITY_ACTION);
    }

    result[module] = moduleMap;
  }

  return result;
}
