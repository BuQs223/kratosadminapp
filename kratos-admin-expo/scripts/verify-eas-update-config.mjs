import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const projectRoot = resolve(import.meta.dirname, '..');
const appConfigPath = resolve(projectRoot, 'app.json');
const appConfig = JSON.parse(await readFile(appConfigPath, 'utf8'));
const expo = appConfig.expo ?? {};
const projectId = expo.extra?.eas?.projectId;
const updateUrl = expo.updates?.url;
const failures = [];

if (typeof projectId !== 'string' || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(projectId)) {
  failures.push('expo.extra.eas.projectId is missing or is not a UUID');
}

if (typeof updateUrl !== 'string' || updateUrl !== `https://u.expo.dev/${projectId}`) {
  failures.push('expo.updates.url must match https://u.expo.dev/<projectId>');
}

if (expo.updates?.requestHeaders?.['expo-channel-name'] !== 'production') {
  failures.push('expo.updates.requestHeaders.expo-channel-name must be production');
}

if (!expo.runtimeVersion) {
  failures.push('expo.runtimeVersion is required for compatible OTA updates');
}

if (failures.length > 0) {
  console.error('EAS Update is not ready for a production Release build:');
  for (const failure of failures) console.error(`- ${failure}`);
  console.error('\nRun `npm run eas:configure`, then regenerate the native projects.');
  process.exitCode = 1;
} else {
  console.log(`EAS Update production configuration verified for project ${projectId}.`);
}
