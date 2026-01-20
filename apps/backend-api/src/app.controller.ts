import { Controller, Get } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { AppService } from './app.service';
import { Public } from './auth/public.decorator';

@ApiTags('Health')
@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get('/health')
  @Public() // health must stay unauthenticated for ALB/SSM probes
  @ApiOperation({
    summary: 'Health check endpoint',
    description: 'Returns service health status. Public endpoint, no authentication required. Used by ALB and monitoring.'
  })
  @ApiResponse({
    status: 200,
    description: 'Service is healthy',
    schema: {
      type: 'object',
      properties: {
        status: { type: 'string', example: 'ok' },
        service: { type: 'string', example: 'backend-api' },
        timestamp: { type: 'string', format: 'date-time', example: '2026-01-19T00:00:00.000Z' }
      }
    }
  })
  health() {
    return this.appService.health();
  }
}
