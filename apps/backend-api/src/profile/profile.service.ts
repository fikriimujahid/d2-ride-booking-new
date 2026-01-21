import { Injectable, NotFoundException, ConflictException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CognitoIdentityProviderClient, AdminUpdateUserAttributesCommand } from '@aws-sdk/client-cognito-identity-provider';
import { DatabaseService } from '../database/database.service';
import { JsonLogger } from '../logging/json-logger.service';
import { Profile } from './profile.entity';
import { CreateProfileDto, UpdateProfileDto } from './profile.dto';
import { randomUUID } from 'crypto';
import { RowDataPacket } from 'mysql2';

/**
 * ProfileService manages user profiles with dual persistence:
 * 1. MySQL database (authoritative source for app data)
 * 2. Cognito user attributes (sync for consistency)
 * 
 * Flow:
 * - Create: Insert to DB → update Cognito attributes
 * - Update: Update DB → sync to Cognito
 * - Read: Query from DB only (fast, no AWS API call)
 * - Delete: Remove from DB → optionally disable Cognito user
 */
@Injectable()
export class ProfileService {
  private cognitoClient: CognitoIdentityProviderClient;
  private userPoolId: string;

  constructor(
    private readonly db: DatabaseService,
    private readonly config: ConfigService,
    private readonly logger: JsonLogger
  ) {
    const region = this.config.get<string>('AWS_REGION') ?? '';
    this.userPoolId = this.config.get<string>('COGNITO_USER_POOL_ID') ?? '';
    this.cognitoClient = new CognitoIdentityProviderClient({ region });
  }

  async create(userId: string, dto: CreateProfileDto): Promise<Profile> {
    const id = randomUUID();
    const role = dto.role ?? 'PASSENGER';

    try {
      await this.db.query`
        INSERT INTO profiles (id, user_id, email, phone_number, full_name, role)
        VALUES (${id}, ${userId}, ${dto.email}, ${dto.phone_number ?? null}, ${dto.full_name ?? null}, ${role})
      `;

      this.logger.log('Profile created in DB', { id, userId });

      // Sync to Cognito (best-effort; log failures but don't block)
      await this.syncToCognito(userId, dto.email, dto.phone_number, dto.full_name, role).catch((err) => {
        this.logger.warn('Cognito sync failed (profile still created)', { error: (err as Error).message });
      });

      return this.findByUserId(userId);
    } catch (error) {
      if ((error as { code?: string }).code === 'ER_DUP_ENTRY') {
        throw new ConflictException('Profile already exists for this user');
      }
      throw error;
    }
  }

  async findByUserId(userId: string): Promise<Profile> {
    const rows = await this.db.query<RowDataPacket[]>`SELECT * FROM profiles WHERE user_id = ${userId} LIMIT 1`;

    if (!rows || rows.length === 0) {
      throw new NotFoundException('Profile not found');
    }

    return rows[0] as Profile;
  }

  async update(userId: string, dto: UpdateProfileDto): Promise<Profile> {
    const existing = await this.findByUserId(userId);

    const updates: Record<string, unknown> = {};
    if (dto.email !== undefined) {
      updates.email = dto.email;
    }
    if (dto.phone_number !== undefined) {
      updates.phone_number = dto.phone_number;
    }
    if (dto.full_name !== undefined) {
      updates.full_name = dto.full_name;
    }
    if (dto.role !== undefined) {
      updates.role = dto.role;
    }

    await this.db.updateByKey('profiles', 'user_id', userId, updates, [
      'email',
      'phone_number',
      'full_name',
      'role'
    ]);

    this.logger.log('Profile updated in DB', { userId });

    // Sync to Cognito
    await this.syncToCognito(
      userId,
      dto.email ?? existing.email,
      dto.phone_number ?? existing.phone_number ?? undefined,
      dto.full_name ?? existing.full_name ?? undefined,
      dto.role ?? existing.role
    ).catch((err) => {
      this.logger.warn('Cognito sync failed after update', { error: (err as Error).message });
    });

    return this.findByUserId(userId);
  }

  async delete(userId: string): Promise<void> {
    await this.findByUserId(userId);

    await this.db.query`DELETE FROM profiles WHERE user_id = ${userId}`;

    this.logger.log('Profile deleted from DB', { userId });
  }

  private async syncToCognito(
    userId: string,
    email: string,
    phoneNumber?: string,
    fullName?: string,
    role?: string
  ): Promise<void> {
    const attributes = [
      { Name: 'email', Value: email },
      { Name: 'email_verified', Value: 'true' }
    ];

    if (phoneNumber) {
      attributes.push({ Name: 'phone_number', Value: phoneNumber });
    }
    if (fullName) {
      attributes.push({ Name: 'name', Value: fullName });
    }
    if (role) {
      attributes.push({ Name: 'custom:role', Value: role });
    }

    const command = new AdminUpdateUserAttributesCommand({
      UserPoolId: this.userPoolId,
      Username: userId,
      UserAttributes: attributes
    });

    await this.cognitoClient.send(command);
    this.logger.log('Cognito attributes synced', { userId });
  }
}
