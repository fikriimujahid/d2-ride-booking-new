import { Test } from '@nestjs/testing';
import { AppController } from './app.controller';
import { AppService } from './app.service';

describe('AppController', () => {
  it('returns health ok', async () => {
    const moduleRef = await Test.createTestingModule({
      controllers: [AppController],
      providers: [AppService]
    }).compile();

    const controller = moduleRef.get(AppController);
    expect(controller.health()).toEqual({ status: 'ok' });
  });
});
