export enum SystemGroup {
  ADMIN = 'ADMIN',
  DRIVER = 'DRIVER',
  PASSENGER = 'PASSENGER'
}

export const SYSTEM_GROUPS: readonly SystemGroup[] = [
  SystemGroup.ADMIN,
  SystemGroup.DRIVER,
  SystemGroup.PASSENGER
] as const;

export function isSystemGroup(value: string): value is SystemGroup {
  return (SYSTEM_GROUPS as readonly string[]).includes(value);
}
