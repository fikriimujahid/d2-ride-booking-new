import { SetMetadata } from '@nestjs/common';

// Mark endpoints that should skip JWT auth (e.g., /health, readiness probes).
export const Public = () => SetMetadata('isPublic', true);
