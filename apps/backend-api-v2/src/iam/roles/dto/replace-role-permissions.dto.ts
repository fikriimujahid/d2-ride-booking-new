import { ArrayUnique, IsArray, IsUUID } from 'class-validator';

export class ReplaceRolePermissionsDto {
  @IsArray()
  @ArrayUnique()
  @IsUUID('4', { each: true })
  permissionIds!: string[];
}
