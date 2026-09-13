import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const projectRoot = resolve(import.meta.dirname, '..');
const flutterEnvPath = resolve(projectRoot, '..', '.env');
const expoEnvPath = resolve(projectRoot, '.env.local');

const source = await readFile(flutterEnvPath, 'utf8');
const values = new Map();

for (const rawLine of source.split(/\r?\n/)) {
  const line = rawLine.trim();
  if (!line || line.startsWith('#')) continue;

  const separator = line.indexOf('=');
  if (separator === -1) continue;
  values.set(line.slice(0, separator).trim(), line.slice(separator + 1).trim());
}

const supabaseUrl = values.get('SUPABASE_URL');
const supabaseKey = values.get('SUPABASE_ANON_KEY');

if (!supabaseUrl || !supabaseKey) {
  throw new Error('The Flutter .env must define SUPABASE_URL and SUPABASE_ANON_KEY.');
}

const output = [
  `EXPO_PUBLIC_SUPABASE_URL=${supabaseUrl}`,
  `EXPO_PUBLIC_SUPABASE_ANON_KEY=${supabaseKey}`,
  'EXPO_PUBLIC_POWERSYNC_URL=https://sync.kratosgym.ro',
  '',
].join('\n');

await writeFile(expoEnvPath, output, { encoding: 'utf8', mode: 0o600 });
console.log('Imported Flutter environment values into kratos-admin-expo/.env.local.');
