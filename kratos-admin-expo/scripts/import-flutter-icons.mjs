import { execFileSync } from 'node:child_process';
import { readdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const projectRoot = resolve(import.meta.dirname, '..');
const flutterAppRoot = resolve(projectRoot, '..');
const flutterBinary = execFileSync('which', ['flutter'], { encoding: 'utf8' }).trim();
const flutterRoot = resolve(dirname(flutterBinary), '..');
const flutterIconsPath = resolve(
  flutterRoot,
  'packages/flutter/lib/src/material/icons.dart',
);

async function dartFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(
    entries.map((entry) => {
      const path = resolve(directory, entry.name);
      if (entry.isDirectory()) return dartFiles(path);
      return entry.name.endsWith('.dart') ? [path] : [];
    }),
  );
  return nested.flat();
}

const usedNames = new Set();
for (const path of await dartFiles(resolve(flutterAppRoot, 'lib'))) {
  const source = await readFile(path, 'utf8');
  for (const match of source.matchAll(/Icons\.([A-Za-z0-9_]+)/g)) usedNames.add(match[1]);
}

const flutterIcons = await readFile(flutterIconsPath, 'utf8');
const codepoints = new Map();
for (const match of flutterIcons.matchAll(
  /static const IconData ([A-Za-z0-9_]+) = IconData\(\s*0x([0-9a-f]+),\s*fontFamily: 'MaterialIcons'/g,
)) {
  codepoints.set(match[1], Number.parseInt(match[2], 16));
}

const missing = [...usedNames].filter((name) => !codepoints.has(name));
if (missing.length) throw new Error(`Missing Flutter icon definitions: ${missing.join(', ')}`);

const entries = [...usedNames]
  .sort()
  .map((name) => `  ${JSON.stringify(name)}: 0x${codepoints.get(name).toString(16)},`)
  .join('\n');
const output =
  `// Generated from the Flutter app and its pinned MaterialIcons font.\n` +
  `// Run npm run icons:import-flutter after adding new Icons.* references in Flutter.\n` +
  `export const materialIconCodepoints = {\n${entries}\n} as const;\n\n` +
  `export type MaterialIconName = keyof typeof materialIconCodepoints;\n`;

await writeFile(resolve(projectRoot, 'src/constants/material-icons.generated.ts'), output);
console.log(`Imported ${usedNames.size} Flutter Material icon codepoints.`);
