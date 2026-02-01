// Phase A: test scaffolding only.
// Unit targets:
// - issuer validation failures -> Unauthorized
// - exp validation failures -> Unauthorized
// - audience/client_id mismatch -> Unauthorized
// - group claim parsing -> correct SystemGroup[]
//
// Mock strategy:
// - DO NOT call remote JWKS in unit tests
// - mock `jose.jwtVerify` / `createRemoteJWKSet` OR wrap jose behind an adapter in Phase B

describe('CognitoJwtStrategy (scaffold)', () => {
  it('TODO', () => {
    expect(true).toBe(true);
  });
});
