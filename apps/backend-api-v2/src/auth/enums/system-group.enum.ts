/**
 * SystemGroup enum - Defines the three system-level user groups in AWS Cognito
 * These groups provide coarse-grained access control for different user types
 * in the ride-booking application
 */
export enum SystemGroup {
  ADMIN = 'ADMIN',        // Administrative users with management access
  DRIVER = 'DRIVER',      // Driver users who provide rides
  PASSENGER = 'PASSENGER' // Passenger users who book rides
}

// Immutable array of all valid system groups for iteration and validation
export const SYSTEM_GROUPS: readonly SystemGroup[] = [
  SystemGroup.ADMIN,
  SystemGroup.DRIVER,
  SystemGroup.PASSENGER
] as const;

/**
 * Type guard function to check if a string is a valid SystemGroup
 * Used for validating JWT claims from Cognito
 * @param value - String value to check
 * @returns true if value is a valid SystemGroup enum value
 */
export function isSystemGroup(value: string): value is SystemGroup {
  // Check if value exists in the SYSTEM_GROUPS array
  return (SYSTEM_GROUPS as readonly string[]).includes(value);
}
