import {
  BadRequestException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  CognitoIdentityProviderClient,
  ConfirmForgotPasswordCommand,
  ConfirmSignUpCommand,
  ForgotPasswordCommand,
  InitiateAuthCommand,
  ResendConfirmationCodeCommand,
  SignUpCommand
} from '@aws-sdk/client-cognito-identity-provider';
import { createHmac } from 'crypto';
import { JsonLogger } from '../logging/json-logger.service';

@Injectable()
export class CognitoAuthService {
  private client: CognitoIdentityProviderClient;
  private clientId: string;
  private clientSecret?: string;

  constructor(private readonly config: ConfigService, private readonly logger: JsonLogger) {
    const region = this.config.get<string>('AWS_REGION') ?? '';
    this.client = new CognitoIdentityProviderClient({ region });
    this.clientId = this.config.get<string>('COGNITO_CLIENT_ID') ?? '';
    this.clientSecret = this.config.get<string>('COGNITO_CLIENT_SECRET');
  }

  assertEnabled() {
    const env = this.config.get<string>('NODE_ENV') ?? 'dev';
    const enabled = (this.config.get<string>('ENABLE_COGNITO_PROXY') ?? '').toLowerCase() === 'true';

    // Default: enabled in non-production (handy for Swagger testing).
    if (env !== 'productions') return;

    // Production: must be explicitly enabled.
    if (!enabled) {
      throw new NotFoundException('Auth proxy is disabled');
    }
  }

  private secretHash(username: string): string | undefined {
    if (!this.clientSecret) return undefined;
    return createHmac('sha256', this.clientSecret).update(username + this.clientId).digest('base64');
  }

  async register(username: string, password: string) {
    this.assertEnabled();

    if (!this.clientId) {
      throw new ServiceUnavailableException('COGNITO_CLIENT_ID is not configured');
    }

    try {
      const command = new SignUpCommand({
        ClientId: this.clientId,
        Username: username,
        Password: password,
        SecretHash: this.secretHash(username),
        UserAttributes: [{ Name: 'email', Value: username }]
      });

      const result = await this.client.send(command);
      this.logger.log('Cognito signUp called', { username });

      return {
        userSub: result.UserSub,
        userConfirmed: result.UserConfirmed,
        codeDeliveryDestination: result.CodeDeliveryDetails?.Destination,
        codeDeliveryMedium: result.CodeDeliveryDetails?.DeliveryMedium
      };
    } catch (error) {
      throw new BadRequestException(this.describeCognitoError(error));
    }
  }

  async confirmSignUp(username: string, code: string) {
    this.assertEnabled();

    try {
      const command = new ConfirmSignUpCommand({
        ClientId: this.clientId,
        Username: username,
        ConfirmationCode: code,
        SecretHash: this.secretHash(username)
      });

      await this.client.send(command);
      this.logger.log('Cognito confirmSignUp called', { username });
      return { ok: true };
    } catch (error) {
      throw new BadRequestException(this.describeCognitoError(error));
    }
  }

  async resendConfirmation(username: string) {
    this.assertEnabled();

    try {
      const command = new ResendConfirmationCodeCommand({
        ClientId: this.clientId,
        Username: username,
        SecretHash: this.secretHash(username)
      });

      const result = await this.client.send(command);
      this.logger.log('Cognito resendConfirmationCode called', { username });

      return {
        ok: true,
        codeDeliveryDestination: result.CodeDeliveryDetails?.Destination,
        codeDeliveryMedium: result.CodeDeliveryDetails?.DeliveryMedium
      };
    } catch (error) {
      throw new BadRequestException(this.describeCognitoError(error));
    }
  }

  async forgotPassword(username: string) {
    this.assertEnabled();

    try {
      const command = new ForgotPasswordCommand({
        ClientId: this.clientId,
        Username: username,
        SecretHash: this.secretHash(username)
      });

      const result = await this.client.send(command);

      return {
        ok: true,
        codeDeliveryDestination: result.CodeDeliveryDetails?.Destination,
        codeDeliveryMedium: result.CodeDeliveryDetails?.DeliveryMedium
      };
    } catch (error) {
      throw new BadRequestException(this.describeCognitoError(error));
    }
  }

  async confirmForgotPassword(username: string, code: string, newPassword: string) {
    this.assertEnabled();

    try {
      const command = new ConfirmForgotPasswordCommand({
        ClientId: this.clientId,
        Username: username,
        ConfirmationCode: code,
        Password: newPassword,
        SecretHash: this.secretHash(username)
      });

      await this.client.send(command);
      return { ok: true };
    } catch (error) {
      throw new BadRequestException(this.describeCognitoError(error));
    }
  }

  async login(username: string, password: string) {
    this.assertEnabled();

    try {
      const command = new InitiateAuthCommand({
        ClientId: this.clientId,
        AuthFlow: 'USER_PASSWORD_AUTH',
        AuthParameters: {
          USERNAME: username,
          PASSWORD: password,
          ...(this.clientSecret ? { SECRET_HASH: this.secretHash(username) ?? '' } : {})
        }
      });

      const result = await this.client.send(command);
      this.logger.log('Cognito initiateAuth called', { username });

      return {
        accessToken: result.AuthenticationResult?.AccessToken,
        idToken: result.AuthenticationResult?.IdToken,
        refreshToken: result.AuthenticationResult?.RefreshToken,
        tokenType: result.AuthenticationResult?.TokenType,
        expiresIn: result.AuthenticationResult?.ExpiresIn,
        challengeName: result.ChallengeName
      };
    } catch (error) {
      throw new BadRequestException(this.describeCognitoError(error));
    }
  }

  async refresh(refreshToken: string, username?: string) {
    this.assertEnabled();

    // SECRET_HASH is required for app clients with a secret; username is needed to compute it.
    if (this.clientSecret && !username) {
      throw new BadRequestException('username is required when using COGNITO_CLIENT_SECRET');
    }

    try {
      const command = new InitiateAuthCommand({
        ClientId: this.clientId,
        AuthFlow: 'REFRESH_TOKEN_AUTH',
        AuthParameters: {
          REFRESH_TOKEN: refreshToken,
          ...(this.clientSecret
            ? { SECRET_HASH: this.secretHash(username ?? '') ?? '' }
            : {})
        }
      });

      const result = await this.client.send(command);

      return {
        accessToken: result.AuthenticationResult?.AccessToken,
        idToken: result.AuthenticationResult?.IdToken,
        tokenType: result.AuthenticationResult?.TokenType,
        expiresIn: result.AuthenticationResult?.ExpiresIn,
        challengeName: result.ChallengeName
      };
    } catch (error) {
      throw new BadRequestException(this.describeCognitoError(error));
    }
  }

  private describeCognitoError(error: unknown): string {
    if (typeof error === 'object' && error !== null) {
      const anyError = error as { name?: string; message?: string };
      if (anyError.message) return anyError.message;
      if (anyError.name) return anyError.name;
    }
    return String(error);
  }
}
