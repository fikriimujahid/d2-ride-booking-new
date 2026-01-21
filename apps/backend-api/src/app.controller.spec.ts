import { Test } from '@nestjs/testing';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { JsonLogger } from './logging/json-logger.service';

describe('AppController', () => {
  it('returns health ok', async () => {
    const moduleRef = await Test.createTestingModule({
      controllers: [AppController],
      providers: [AppService, JsonLogger]
    }).compile();

    const controller = moduleRef.get(AppController);
    const result = controller.health();
    expect(result).toMatchObject({ status: 'ok', service: 'backend-api' });
    expect(result.timestamp).toBeDefined();
  });
});
