import { IsOptional, IsString, MaxLength } from 'class-validator';

export class CreatePermissionDto {
  @IsString()
  @MaxLength(128)
  key!: string;

  @IsOptional()
  @IsString()
  @MaxLength(255)
  description?: string;
}
