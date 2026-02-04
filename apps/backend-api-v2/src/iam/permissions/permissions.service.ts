import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';

@Injectable()
export class PermissionsService {
  constructor(private readonly prisma: PrismaService) {}

  async upsertPermission(params: { key: string; description?: string }) {
    return this.prisma.permission.upsert({
      where: { key: params.key },
      update: { description: params.description, deletedAt: null },
      create: { key: params.key, description: params.description }
    });
  }
}
