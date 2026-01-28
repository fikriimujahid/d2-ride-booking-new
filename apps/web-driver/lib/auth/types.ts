export type Role = 'ADMIN' | 'DRIVER' | 'PASSENGER';

export type AuthTokens = {
  accessToken: string;
  idToken: string;
  accessTokenExp: number;
  idTokenExp: number;
};

export type AuthUser = {
  email?: string;
  role?: Role;
  sub?: string;
};
