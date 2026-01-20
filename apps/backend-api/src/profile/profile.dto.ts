import { IsEmail, IsEnum, IsNotEmpty, IsOptional, IsString, MaxLength } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class CreateProfileDto {
  @ApiProperty({
    description: 'User email address',
    example: 'john.doe@example.com',
    format: 'email'
  })
  @IsEmail()
  @IsNotEmpty()
  email!: string;

  @ApiPropertyOptional({
    description: 'User phone number (E.164 format recommended)',
    example: '+6281234567890',
    maxLength: 20
  })
  @IsString()
  @IsOptional()
  @MaxLength(20)
  phone_number?: string;

  @ApiPropertyOptional({
    description: 'User full name',
    example: 'John Doe',
    maxLength: 255
  })
  @IsString()
  @IsOptional()
  @MaxLength(255)
  full_name?: string;

  @ApiPropertyOptional({
    description: 'User role for RBAC',
    enum: ['ADMIN', 'DRIVER', 'PASSENGER'],
    default: 'PASSENGER',
    example: 'PASSENGER'
  })
  @IsEnum(['ADMIN', 'DRIVER', 'PASSENGER'])
  @IsOptional()
  role?: 'ADMIN' | 'DRIVER' | 'PASSENGER';
}

export class UpdateProfileDto {
  @ApiPropertyOptional({
    description: 'User email address',
    example: 'jane.doe@example.com',
    format: 'email'
  })
  @IsEmail()
  @IsOptional()
  email?: string;

  @ApiPropertyOptional({
    description: 'User phone number (E.164 format recommended)',
    example: '+6289876543210',
    maxLength: 20
  })
  @IsString()
  @IsOptional()
  @MaxLength(20)
  phone_number?: string;

  @ApiPropertyOptional({
    description: 'User full name',
    example: 'Jane Doe',
    maxLength: 255
  })
  @IsString()
  @IsOptional()
  @MaxLength(255)
  full_name?: string;

  @ApiPropertyOptional({
    description: 'User role for RBAC',
    enum: ['ADMIN', 'DRIVER', 'PASSENGER'],
    example: 'DRIVER'
  })
  @IsEnum(['ADMIN', 'DRIVER', 'PASSENGER'])
  @IsOptional()
  role?: 'ADMIN' | 'DRIVER' | 'PASSENGER';
}
