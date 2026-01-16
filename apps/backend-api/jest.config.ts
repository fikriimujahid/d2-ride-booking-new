import type { Config } from 'jest';

const config: Config = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  testMatch: ['**/*.spec.ts'],
  roots: ['<rootDir>/src'],
  clearMocks: true
};

export default config;
