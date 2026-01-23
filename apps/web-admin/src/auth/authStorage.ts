/**
 * Why not localStorage?
 * - For DEV we prefer short-lived storage to reduce token persistence risk.
 * - sessionStorage is per-tab and clears on tab close.
 * - This also avoids long-lived tokens surviving browser restarts.
 */
class MemoryStorage implements Storage {
  #mem = new Map<string, string>();

  get length(): number {
    return this.#mem.size;
  }

  clear(): void {
    this.#mem.clear();
  }

  getItem(key: string): string | null {
    return this.#mem.get(key) ?? null;
  }

  key(index: number): string | null {
    return Array.from(this.#mem.keys())[index] ?? null;
  }

  removeItem(key: string): void {
    this.#mem.delete(key);
  }

  setItem(key: string, value: string): void {
    this.#mem.set(key, value);
  }
}

const memoryStorage = new MemoryStorage();

export function getSessionStorage(): Storage {
  // Guard for SSR/test environments.
  const maybeSessionStorage = (globalThis as { sessionStorage?: Storage }).sessionStorage;
  return maybeSessionStorage ?? memoryStorage;
}
