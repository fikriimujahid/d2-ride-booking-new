import { IsEmail, IsEnum, IsOptional, MaxLength } from 'class-validator';
import { AdminUserStatus } from '@prisma/client';

export class UpdateAdminUserDto {
  @IsOptional()
  @IsEmail()
  @MaxLength(320)
  email?: string;

  @IsOptional()
  @IsEnum(AdminUserStatus)
  status?: AdminUserStatus;
}
