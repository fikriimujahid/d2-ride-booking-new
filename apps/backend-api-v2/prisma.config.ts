import 'dotenv/config';
import { defineConfig } from 'prisma/config';

// Prisma ORM v7: datasource URL is configured here (not in schema.prisma).
// Use process.env directly so `prisma generate` can run even when DATABASE_URL
// is not set (e.g., Phase A-only runs).
const DATABASE_URL_FALLBACK = 'mysql://root:password@localhost:3306/d2_rbac_dev';

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
    seed: 'ts-node prisma/seed.ts'
  },
  datasource: {
    url: process.env.DATABASE_URL ?? DATABASE_URL_FALLBACK,
    shadowDatabaseUrl: process.env.SHADOW_DATABASE_URL
  }
});
