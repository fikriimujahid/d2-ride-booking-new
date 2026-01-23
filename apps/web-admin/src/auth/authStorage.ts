/**
 * Why not localStorage?
 * - For DEV we prefer short-lived storage to reduce token persistence risk.
 * - sessionStorage is per-tab and clears on tab close.
 * - This also avoids long-lived tokens surviving browser restarts.
 */
export function getSessionStorage(): Pick<Storage, 'getItem' | 'setItem' | 'removeItem'> {
  // Guard for SSR (not used in Vite, but keeps the module safe and testable).
  if (typeof window === 'undefined') {
    const mem = new Map<string, string>();
    return {
      getItem: (key) => mem.get(key) ?? null,
      setItem: (key, value) => {
        mem.set(key, value);
      },
      removeItem: (key) => {
        mem.delete(key);
      }
    };
  }

  return {
    getItem: (key) => window.sessionStorage.getItem(key),
    setItem: (key, value) => window.sessionStorage.setItem(key, value),
    removeItem: (key) => window.sessionStorage.removeItem(key)
  };
}
