import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const target = join(
  projectRoot,
  'node_modules',
  'expo-modules-jsi',
  'apple',
  'Sources',
  'ExpoModulesJSI',
  'Coding',
  'JavaScriptCodable+Date.swift',
);
const before = 'abs(milliseconds) <= maxJavaScriptDateMilliseconds';
const after = 'milliseconds.magnitude <= maxJavaScriptDateMilliseconds';

let source;
try {
  source = readFileSync(target, 'utf8');
} catch (error) {
  console.error(`Unable to read ${target}:`, error);
  process.exitCode = 1;
  process.exit();
}

if (source.includes(after)) {
  console.log('expo-modules-jsi Xcode 26 compatibility patch is already applied.');
  process.exit();
}

if (!source.includes(before)) {
  console.error(
    'expo-modules-jsi changed upstream; refusing to apply an unverified Xcode 26 compatibility patch.',
  );
  process.exitCode = 1;
  process.exit();
}

writeFileSync(target, source.replace(before, after));
console.log('Applied expo-modules-jsi Xcode 26 compatibility patch.');
