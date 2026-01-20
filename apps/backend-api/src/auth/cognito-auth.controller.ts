import { Body, Controller, Post } from '@nestjs/common';
import { ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';
import { Public } from './public.decorator';
import {
  CognitoConfirmSignUpDto,
  CognitoConfirmForgotPasswordDto,
  CognitoDeliveryDetailsResponseDto,
  CognitoForgotPasswordDto,
  CognitoLoginDto,
  CognitoOkResponseDto,
  CognitoRefreshDto,
  CognitoRegisterDto,
  CognitoRegisterResponseDto,
  CognitoResendConfirmationDto,
  CognitoTokenResponseDto
} from './cognito-auth.dto';
import { CognitoAuthService } from './cognito-auth.service';

@ApiTags('Auth')
@Controller('auth')
export class CognitoAuthController {
  constructor(private readonly cognito: CognitoAuthService) {}

  @Post('register')
  @Public()
  @ApiOperation({
    summary: 'Register user (Cognito SignUp)',
    description:
      'Convenience endpoint for Swagger testing. Creates a user in AWS Cognito (not Hosted UI). ' +
      'Typically used in local/dev only.'
  })
  @ApiResponse({ status: 201, type: CognitoRegisterResponseDto })
  @ApiResponse({ status: 400, description: 'Cognito rejected the request (invalid password, user exists, etc).' })
  async register(@Body() body: CognitoRegisterDto): Promise<CognitoRegisterResponseDto> {
    return this.cognito.register(body.username, body.password);
  }

  @Post('confirm')
  @Public()
  @ApiOperation({
    summary: 'Confirm registration (Cognito ConfirmSignUp)',
    description: 'Confirms a newly registered user using the code sent by Cognito.'
  })
  @ApiResponse({ status: 201, type: CognitoOkResponseDto })
  @ApiResponse({ status: 400, description: 'Invalid/expired code or user not found.' })
  async confirm(@Body() body: CognitoConfirmSignUpDto): Promise<CognitoOkResponseDto> {
    return this.cognito.confirmSignUp(body.username, body.code);
  }

  @Post('resend-confirmation')
  @Public()
  @ApiOperation({
    summary: 'Resend confirmation code (Cognito ResendConfirmationCode)',
    description: 'Resends the sign-up confirmation code for an unconfirmed user.'
  })
  @ApiResponse({ status: 201, type: CognitoDeliveryDetailsResponseDto })
  @ApiResponse({ status: 400, description: 'User not found or already confirmed, etc.' })
  async resendConfirmation(
    @Body() body: CognitoResendConfirmationDto
  ): Promise<CognitoDeliveryDetailsResponseDto> {
    return this.cognito.resendConfirmation(body.username);
  }

  @Post('login')
  @Public()
  @ApiOperation({
    summary: 'Login (Cognito InitiateAuth USER_PASSWORD_AUTH)',
    description:
      'Returns Cognito tokens (access/id/refresh) so you can paste the access token into Swagger Authorize.'
  })
  @ApiResponse({ status: 201, type: CognitoTokenResponseDto })
  @ApiResponse({ status: 400, description: 'Not authorized, user not confirmed, etc.' })
  async login(@Body() body: CognitoLoginDto): Promise<CognitoTokenResponseDto> {
    return this.cognito.login(body.username, body.password);
  }

  @Post('refresh')
  @Public()
  @ApiOperation({
    summary: 'Refresh tokens (Cognito InitiateAuth REFRESH_TOKEN_AUTH)',
    description:
      'Uses a refresh token to obtain a new access/id token pair. Refresh tokens are usually only returned from /auth/login.'
  })
  @ApiResponse({ status: 201, type: CognitoTokenResponseDto })
  @ApiResponse({ status: 400, description: 'Invalid refresh token, or missing username when client secret is used.' })
  async refresh(@Body() body: CognitoRefreshDto): Promise<CognitoTokenResponseDto> {
    return this.cognito.refresh(body.refreshToken, body.username);
  }

  @Post('forgot-password')
  @Public()
  @ApiOperation({
    summary: 'Start forgot-password flow (Cognito ForgotPassword)',
    description: 'Sends a password reset code via the configured delivery method (email/SMS).'
  })
  @ApiResponse({ status: 201, type: CognitoDeliveryDetailsResponseDto })
  @ApiResponse({ status: 400, description: 'User not found, throttled, etc.' })
  async forgotPassword(@Body() body: CognitoForgotPasswordDto): Promise<CognitoDeliveryDetailsResponseDto> {
    return this.cognito.forgotPassword(body.username);
  }

  @Post('confirm-forgot-password')
  @Public()
  @ApiOperation({
    summary: 'Confirm forgot-password (Cognito ConfirmForgotPassword)',
    description: 'Completes the forgot-password flow by setting a new password.'
  })
  @ApiResponse({ status: 201, type: CognitoOkResponseDto })
  @ApiResponse({ status: 400, description: 'Invalid/expired code or password policy violation.' })
  async confirmForgotPassword(@Body() body: CognitoConfirmForgotPasswordDto): Promise<CognitoOkResponseDto> {
    return this.cognito.confirmForgotPassword(body.username, body.code, body.newPassword);
  }
}
