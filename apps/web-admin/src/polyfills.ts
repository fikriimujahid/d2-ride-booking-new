// Polyfills needed for certain browser-compatible Node libs.
//
// Why:
// - `amazon-cognito-identity-js` pulls in dependencies that assume `Buffer` and/or `process`
//   exist (common in packages that run in both Node and browsers).
// - Vite does not automatically inject Node polyfills.

import { Buffer } from 'buffer';
import process from 'process';

const g = globalThis as any;

if (typeof g.Buffer === 'undefined') {
  g.Buffer = Buffer;
}

if (typeof g.process === 'undefined') {
  g.process = process;
}
