import {
  Body,
  Controller,
  Delete,
  Get,
  Post,
  Put,
  Request,
  HttpCode,
  HttpStatus
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiBody,
  ApiBadRequestResponse,
  ApiUnauthorizedResponse,
  ApiNotFoundResponse,
  ApiConflictResponse
} from '@nestjs/swagger';
import { ProfileService } from './profile.service';
import { CreateProfileDto, UpdateProfileDto } from './profile.dto';
import { ProfileResponseDto } from './profile.entity';

/**
 * ProfileController exposes CRUD endpoints for authenticated users.
 * JWT guard is global, so all routes require valid Cognito token.
 * user_id is extracted from JWT payload (request.user.sub).
 */
@ApiTags('Profile')
@ApiBearerAuth('cognito-jwt')
@ApiUnauthorizedResponse({ description: 'Missing or invalid JWT token' })
@Controller('profile')
export class ProfileController {
  constructor(private readonly profileService: ProfileService) {}

  /**
   * POST /profile
   * Create profile for authenticated user
   */
  @Post()
  @ApiOperation({
    summary: 'Create user profile',
    description:
      'Creates a new profile for the authenticated user. User ID is extracted from JWT token (sub claim). ' +
      'Profile data is stored in MySQL and synced to Cognito user attributes.'
  })
  @ApiBody({ type: CreateProfileDto })
  @ApiResponse({
    status: 201,
    description: 'Profile created successfully',
    type: ProfileResponseDto
  })
  @ApiBadRequestResponse({ description: 'Invalid input data (validation failed)' })
  @ApiConflictResponse({ description: 'Profile already exists for this user' })
  async create(
    @Request() req: { user: { sub: string } },
    @Body() dto: CreateProfileDto
  ): Promise<ProfileResponseDto> {
    return this.profileService.create(req.user.sub, dto);
  }

  /**
   * GET /profile
   * Get current user's profile
   */
  @Get()
  @ApiOperation({
    summary: 'Get current user profile',
    description: 'Retrieves the profile for the authenticated user based on JWT token.'
  })
  @ApiResponse({
    status: 200,
    description: 'Profile retrieved successfully',
    type: ProfileResponseDto
  })
  @ApiNotFoundResponse({ description: 'Profile not found for this user' })
  async getProfile(@Request() req: { user: { sub: string } }): Promise<ProfileResponseDto> {
    return this.profileService.findByUserId(req.user.sub);
  }

  /**
   * PUT /profile
   * Update current user's profile
   */
  @Put()
  @ApiOperation({
    summary: 'Update user profile',
    description:
      'Updates the authenticated user\'s profile. All fields are optional. ' +
      'Changes are saved to MySQL and synced to Cognito.'
  })
  @ApiBody({ type: UpdateProfileDto })
  @ApiResponse({
    status: 200,
    description: 'Profile updated successfully',
    type: ProfileResponseDto
  })
  @ApiBadRequestResponse({ description: 'Invalid input data' })
  @ApiNotFoundResponse({ description: 'Profile not found' })
  async update(
    @Request() req: { user: { sub: string } },
    @Body() dto: UpdateProfileDto
  ): Promise<ProfileResponseDto> {
    return this.profileService.update(req.user.sub, dto);
  }

  /**
   * DELETE /profile
   * Delete current user's profile
   */
  @Delete()
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    summary: 'Delete user profile',
    description: 'Deletes the authenticated user\'s profile from the database. Cognito user remains active.'
  })
  @ApiResponse({
    status: 204,
    description: 'Profile deleted successfully'
  })
  @ApiNotFoundResponse({ description: 'Profile not found' })
  async delete(@Request() req: { user: { sub: string } }): Promise<void> {
    return this.profileService.delete(req.user.sub);
  }
}
