/**
 * Driver app runs on EC2 (Next.js server), but auth happens client-side.
 * We keep token storage short-lived via sessionStorage.
 */
export function getSessionStorage(): Pick<Storage, 'getItem' | 'setItem' | 'removeItem'> {
  if (typeof window === 'undefined') {
    const mem = new Map<string, string>();
    return {
      getItem: (k) => mem.get(k) ?? null,
      setItem: (k, v) => {
        mem.set(k, v);
      },
      removeItem: (k) => {
        mem.delete(k);
      }
    };
  }

  return {
    getItem: (k) => window.sessionStorage.getItem(k),
    setItem: (k, v) => window.sessionStorage.setItem(k, v),
    removeItem: (k) => window.sessionStorage.removeItem(k)
  };
}
