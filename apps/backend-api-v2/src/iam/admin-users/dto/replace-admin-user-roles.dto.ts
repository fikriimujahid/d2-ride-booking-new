import { ArrayUnique, IsArray, IsUUID } from 'class-validator';

export class ReplaceAdminUserRolesDto {
  @IsArray()
  @ArrayUnique()
  @IsUUID('4', { each: true })
  roleIds!: string[];
}
