import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';

const projectRoot = resolve(import.meta.dirname, '..');
const requiredVariables = [
  'EXPO_PUBLIC_SUPABASE_URL',
  'EXPO_PUBLIC_SUPABASE_ANON_KEY',
  'EXPO_PUBLIC_POWERSYNC_URL',
];

const result = spawnSync(
  process.platform === 'win32' ? 'npx.cmd' : 'npx',
  ['eas-cli@latest', 'env:list', 'production'],
  { cwd: projectRoot, encoding: 'utf8' },
);

if (result.status !== 0) {
  console.error('Unable to verify the Braitech EAS production environment.');
  console.error(result.stderr.trim() || result.stdout.trim());
  process.exit(1);
}

const output = `${result.stdout}\n${result.stderr}`;
const missingVariables = requiredVariables.filter((name) => !output.includes(name));

if (missingVariables.length > 0) {
  console.error('EAS production is missing variables required by the app bundle:');
  for (const name of missingVariables) console.error(`- ${name}`);
  console.error('\nRun `npx eas-cli@latest env:push production --path .env.local --force`.');
  process.exit(1);
}

console.log(`EAS production environment verified (${requiredVariables.join(', ')}).`);
