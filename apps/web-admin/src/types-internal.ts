// Internal shared types to avoid circular imports.
export type AuthContextValue = {
  getAccessToken: () => string | null;
  signOut: () => void;
};
