import { ApiProperty } from '@nestjs/swagger';

export interface Profile {
  id: string;
  user_id: string;
  email: string;
  phone_number: string | null;
  full_name: string | null;
  role: 'ADMIN' | 'DRIVER' | 'PASSENGER';
  created_at: Date;
  updated_at: Date;
}

export type ProfileRole = Profile['role'];

// Swagger schema representation
export class ProfileResponseDto implements Profile {
  @ApiProperty({
    description: 'Profile unique identifier (UUID)',
    example: '123e4567-e89b-12d3-a456-426614174000',
    format: 'uuid'
  })
  id!: string;

  @ApiProperty({
    description: 'Cognito user ID (sub claim from JWT)',
    example: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
  })
  user_id!: string;

  @ApiProperty({
    description: 'User email address',
    example: 'john.doe@example.com'
  })
  email!: string;

  @ApiProperty({
    description: 'User phone number',
    example: '+6281234567890',
    nullable: true
  })
  phone_number!: string | null;

  @ApiProperty({
    description: 'User full name',
    example: 'John Doe',
    nullable: true
  })
  full_name!: string | null;

  @ApiProperty({
    description: 'User role for RBAC',
    enum: ['ADMIN', 'DRIVER', 'PASSENGER'],
    example: 'PASSENGER'
  })
  role!: 'ADMIN' | 'DRIVER' | 'PASSENGER';

  @ApiProperty({
    description: 'Profile creation timestamp',
    example: '2026-01-19T00:00:00.000Z',
    format: 'date-time'
  })
  created_at!: Date;

  @ApiProperty({
    description: 'Profile last update timestamp',
    example: '2026-01-19T00:00:00.000Z',
    format: 'date-time'
  })
  updated_at!: Date;
}
