import { IsEmail, IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';
import { AdminUserStatus } from '@prisma/client';

export class CreateAdminUserDto {
  @IsString()
  @MaxLength(64)
  cognitoSub!: string;

  @IsEmail()
  @MaxLength(320)
  email!: string;

  @IsOptional()
  @IsEnum(AdminUserStatus)
  status?: AdminUserStatus;
}
