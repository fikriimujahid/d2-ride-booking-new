/**
 * Driver app runs on EC2 (Next.js server), but auth happens client-side.
 * We keep token storage short-lived via sessionStorage.
 */
export function getSessionStorage(): Storage {
  if (typeof window === 'undefined') {
    const mem = new Map<string, string>();
    return {
      getItem: (k) => mem.get(k) ?? null,
      setItem: (k, v) => {
        mem.set(k, v);
      },
      removeItem: (k) => {
        mem.delete(k);
      },
      clear: () => {
        mem.clear();
      },
      key: (index) => {
        const keys = Array.from(mem.keys());
        return keys[index] ?? null;
      },
      get length() {
        return mem.size;
      }
    };
  }

  return window.sessionStorage;
}
