import { permissionMatches } from '../../../src/iam/rbac/permission.service';

describe('permissionMatches', () => {
  it('matches exact permission', () => {
    expect(permissionMatches('dashboard:view', 'dashboard:view')).toBe(true);
  });

  it('wildcard * grants everything', () => {
    expect(permissionMatches('dashboard:view', '*')).toBe(true);
    expect(permissionMatches('driver:manage', '*')).toBe(true);
  });

  it('segment wildcard grants resource:*', () => {
    expect(permissionMatches('driver:read', 'driver:*')).toBe(true);
    expect(permissionMatches('driver:manage', 'driver:*')).toBe(true);
    expect(permissionMatches('passenger:manage', 'driver:*')).toBe(false);
  });

  it('segment wildcard grants *:action', () => {
    expect(permissionMatches('driver:read', '*:read')).toBe(true);
    expect(permissionMatches('driver:manage', '*:read')).toBe(false);
  });
});
