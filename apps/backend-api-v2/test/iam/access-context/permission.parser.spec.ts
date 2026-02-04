import { buildModuleAccessMap, parsePermissionKey } from '../../../src/iam/access-context/permission.parser';

describe('parsePermissionKey', () => {
  it('parses <module>:<action>', () => {
    expect(parsePermissionKey('driver:update')).toEqual({ module: 'driver', action: 'update' });
  });

  it('rejects missing colon', () => {
    expect(parsePermissionKey('driver')).toBeNull();
  });

  it('rejects empty module', () => {
    expect(parsePermissionKey(':read')).toBeNull();
  });

  it('rejects empty action', () => {
    expect(parsePermissionKey('driver:')).toBeNull();
  });

  it('rejects extra colons', () => {
    expect(parsePermissionKey('a:b:c')).toBeNull();
  });
});

describe('buildModuleAccessMap', () => {
  it('builds module/action universe from catalog and defaults to false', () => {
    const modules = buildModuleAccessMap({
      allPermissionKeys: ['dashboard:view', 'dashboard:read', 'driver:view', 'driver:update'],
      grantedPermissionKeys: []
    });

    expect(modules.dashboard.view).toBe(false);
    expect(modules.dashboard.read).toBe(false);
    expect(modules.driver.view).toBe(false);
    expect(modules.driver.update).toBe(false);
  });

  it('sets granted permissions to true and keeps others false', () => {
    const modules = buildModuleAccessMap({
      allPermissionKeys: ['dashboard:view', 'dashboard:read', 'driver:view', 'driver:update', 'driver:delete'],
      grantedPermissionKeys: ['dashboard:view', 'driver:update']
    });

    expect(modules.dashboard.view).toBe(true);
    expect(modules.dashboard.read).toBe(false);
    expect(modules.driver.view).toBe(false);
    expect(modules.driver.update).toBe(true);
    expect(modules.driver.delete).toBe(false);
  });

  it('ensures view is present for each module even if not in catalog', () => {
    const modules = buildModuleAccessMap({
      allPermissionKeys: ['report:generate'],
      grantedPermissionKeys: []
    });

    expect(modules.report.view).toBe(false);
    expect(modules.report.generate).toBe(false);
  });

  it('ignores malformed permission strings', () => {
    const modules = buildModuleAccessMap({
      allPermissionKeys: ['dashboard:view', 'bad', '*', 'a:b:c'],
      grantedPermissionKeys: ['bad', '*', 'dashboard:view']
    });

    expect(modules.dashboard.view).toBe(true);
    expect(Object.keys(modules)).toEqual(['dashboard']);
  });
});
