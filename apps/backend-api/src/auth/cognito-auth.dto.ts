import { ApiProperty } from '@nestjs/swagger';
import { IsEmail, IsOptional, IsString, MinLength } from 'class-validator';

export class CognitoRegisterDto {
  @ApiProperty({
    description: 'Username for Cognito. In this demo we use email as the username.',
    example: 'user@example.com'
  })
  @IsEmail()
  username!: string;

  @ApiProperty({
    description: 'Password for Cognito user (must satisfy your User Pool password policy).',
    example: 'YourPassword123!'
  })
  @IsString()
  @MinLength(8)
  password!: string;
}

export class CognitoConfirmSignUpDto {
  @ApiProperty({
    description: 'Username used during sign-up (email in this demo).',
    example: 'user@example.com'
  })
  @IsEmail()
  username!: string;

  @ApiProperty({
    description: 'Confirmation code sent by Cognito via email/SMS.',
    example: '123456'
  })
  @IsString()
  code!: string;
}

export class CognitoResendConfirmationDto {
  @ApiProperty({
    description: 'Username (email) to resend the confirmation code for.',
    example: 'user@example.com'
  })
  @IsEmail()
  username!: string;
}

export class CognitoForgotPasswordDto {
  @ApiProperty({
    description: 'Username (email) for the Cognito user who forgot their password.',
    example: 'user@example.com'
  })
  @IsEmail()
  username!: string;
}

export class CognitoConfirmForgotPasswordDto {
  @ApiProperty({
    description: 'Username (email) for the Cognito user.',
    example: 'user@example.com'
  })
  @IsEmail()
  username!: string;

  @ApiProperty({
    description: 'Confirmation code sent by Cognito for the password reset.',
    example: '123456'
  })
  @IsString()
  code!: string;

  @ApiProperty({
    description: 'New password (must satisfy your User Pool password policy).',
    example: 'YourNewPassword123!'
  })
  @IsString()
  @MinLength(8)
  newPassword!: string;
}

export class CognitoLoginDto {
  @ApiProperty({
    description: 'Username (email) for Cognito user.',
    example: 'user@example.com'
  })
  @IsEmail()
  username!: string;

  @ApiProperty({
    description: 'Password for Cognito user.',
    example: 'YourPassword123!'
  })
  @IsString()
  password!: string;
}

export class CognitoRefreshDto {
  @ApiProperty({
    description: 'Refresh token returned by /auth/login. Used to get new access/id tokens.',
    example: 'eyJjdHkiOiJKV1QiLCJhbGciOiJ...'
  })
  @IsString()
  refreshToken!: string;

  @ApiProperty({
    description: 'Username (email). Only required when using app clients with a secret (SECRET_HASH).',
    example: 'user@example.com',
    required: false
  })
  @IsOptional()
  @IsEmail()
  username?: string;
}

export class CognitoTokenResponseDto {
  @ApiProperty({ required: false, description: 'JWT access token.' })
  accessToken?: string;

  @ApiProperty({ required: false, description: 'JWT ID token (contains user claims).' })
  idToken?: string;

  @ApiProperty({ required: false, description: 'Refresh token (only returned on initial auth).' })
  refreshToken?: string;

  @ApiProperty({ required: false, description: 'Token type (usually Bearer).' })
  tokenType?: string;

  @ApiProperty({ required: false, description: 'Expires in seconds.' })
  expiresIn?: number;

  @ApiProperty({
    required: false,
    description: 'Present when Cognito requires an additional challenge (e.g. NEW_PASSWORD_REQUIRED).'
  })
  challengeName?: string;
}

export class CognitoRegisterResponseDto {
  @ApiProperty({ required: false })
  userSub?: string;

  @ApiProperty({ required: false })
  userConfirmed?: boolean;

  @ApiProperty({ required: false })
  codeDeliveryDestination?: string;

  @ApiProperty({ required: false })
  codeDeliveryMedium?: string;
}

export class CognitoDeliveryDetailsResponseDto {
  @ApiProperty({ example: true })
  ok!: boolean;

  @ApiProperty({ required: false })
  codeDeliveryDestination?: string;

  @ApiProperty({ required: false })
  codeDeliveryMedium?: string;
}

export class CognitoOkResponseDto {
  @ApiProperty({ example: true })
  ok!: boolean;
}
