const { existsSync } = require('node:fs');
const { writeFile } = require('node:fs/promises');
const { homedir } = require('node:os');
const { join } = require('node:path');
const {
  withDangerousMod,
  withGradleProperties,
  withPodfileProperties,
} = require('@expo/config-plugins');

const androidStudioJavaHome = '/Applications/Android Studio.app/Contents/jbr/Contents/Home';

function upsertGradleProperty(properties, key, value) {
  const existing = properties.find(
    (property) => property.type === 'property' && property.key === key,
  );

  if (existing) existing.value = value;
  else properties.push({ type: 'property', key, value });
}

function withAndroidGradleMemory(config) {
  return withGradleProperties(config, (modConfig) => {
    upsertGradleProperty(
      modConfig.modResults,
      'org.gradle.jvmargs',
      '-Xmx3072m -XX:MaxMetaspaceSize=1024m',
    );
    return modConfig;
  });
}

function withCompatibleAndroidJavaHome(config) {
  const configuredJavaHome = process.env.KRATOS_ANDROID_JAVA_HOME;
  const javaHome = configuredJavaHome || (existsSync(androidStudioJavaHome) ? androidStudioJavaHome : null);

  if (!javaHome) return config;

  return withGradleProperties(config, (modConfig) => {
    upsertGradleProperty(modConfig.modResults, 'org.gradle.java.home', javaHome);
    return modConfig;
  });
}

function escapeJavaProperty(value) {
  return value.replaceAll('\\', '\\\\').replaceAll(':', '\\:');
}

function withLocalAndroidSdk(config) {
  return withDangerousMod(config, [
    'android',
    async (modConfig) => {
      const defaultSdkRoot = join(homedir(), 'Library', 'Android', 'sdk');
      const configuredSdkRoot =
        process.env.KRATOS_ANDROID_SDK_ROOT ||
        process.env.ANDROID_HOME ||
        process.env.ANDROID_SDK_ROOT;
      const sdkRoot = configuredSdkRoot || (existsSync(defaultSdkRoot) ? defaultSdkRoot : null);

      if (sdkRoot) {
        const localProperties = join(modConfig.modRequest.platformProjectRoot, 'local.properties');
        await writeFile(localProperties, `sdk.dir=${escapeJavaProperty(sdkRoot)}\n`, 'utf8');
      }

      return modConfig;
    },
  ]);
}

module.exports = function withPowerSyncUpdatesSqlite(config) {
  const withSqlitePod = withPodfileProperties(config, (modConfig) => {
    modConfig.modResults['expo.updates.useThirdPartySQLitePod'] = 'true';
    return modConfig;
  });

  return withLocalAndroidSdk(
    withCompatibleAndroidJavaHome(withAndroidGradleMemory(withSqlitePod)),
  );
};
