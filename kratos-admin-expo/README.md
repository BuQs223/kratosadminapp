# Kratos Admin — Expo React Native

This is the React Native/Expo port of the Kratos Gym Admin Flutter application. It keeps the existing Supabase backend, uses PowerSync with OP-SQLite for the local/offline database, and is configured for production OTA delivery through EAS Update.

## Included application areas

- Authentication, session persistence, splash routing, and logout
- Dashboard and gym switching
- Members, details, editing, membership CRUD, history, and revenue history
- Membership freeze/resume and scheduled freezes from the client profile ([behavior and synchronization](MEMBERSHIP_FREEZE.md))
- Check-ins, filtering, statistics, and Gold/Silver analysis
- Revenue, filters, search, CSV export, editing/deleting/restoring, analytics, and period comparison
- Gyms and membership-plan administration

The legacy Products console and Performance Monitor are intentionally excluded from the active admin navigation because those Flutter areas are obsolete.

## Prerequisites

- Node.js and npm
- Xcode 26.4+ and CocoaPods for iOS (Expo SDK 57's supported baseline)
- Android Studio with Android SDK 36, Build Tools 36, NDK 27.1, and its bundled JDK 21
- An Expo account with access to the EAS project
- A connected device with developer mode enabled

The config plugin automatically uses Android Studio's bundled JDK 21 and the standard macOS Android SDK location when they exist. On a different setup, define `KRATOS_ANDROID_JAVA_HOME` and `KRATOS_ANDROID_SDK_ROOT` before prebuilding.

## First-time setup

```bash
cd kratos-admin-expo
npm install
npm run env:import-flutter
```

The import command reads the parent Flutter project's `.env` and writes an ignored `.env.local`. For a standalone checkout, copy `.env.example` to `.env.local` and fill in the three public values instead.

Sync those public client values to the EAS production environment before publishing updates:

```bash
npx eas-cli@latest env:push production --path .env.local --force
```

Expo SDK 55 and later use only the selected EAS environment when `eas update --environment production` runs; local `.env` files are ignored for that update bundle. The production-update script verifies that all three required variables exist remotely before it publishes.

Link the app to its Expo owner and generate the EAS Update URL once:

```bash
npm run eas:configure
```

Choose the intended Expo account when prompted. This adds `extra.eas.projectId` and `updates.url` to `app.json`. Commit those non-secret identifiers. If native folders already exist, regenerate them afterward:

```bash
npx expo prebuild --clean
```

The Release scripts run `npm run verify:eas-update` first and stop with an actionable error if the project ID or update URL is missing or inconsistent. Production updates additionally run `npm run verify:eas-production-env` to prevent publishing a bundle without its Supabase and PowerSync configuration.

The generated `android/` and `ios/` folders are intentionally ignored; the committed Expo config and config plugin recreate them.

## Development builds

This app requires its own development build. Expo Go does not include the native OP-SQLite module used by PowerSync and will fail at startup with `Base module not found. Did you do a pod install/clear the gradle cache?`. Starting Metro or clearing its cache cannot add a native module to Expo Go.

These commands create Debug builds and use Metro. They are for development, not the persistent production OTA installation:

```bash
npx expo run:android --device
npx expo run:ios --device
```

Equivalent shortcuts:

```bash
npm run android
npm run ios
```

Run the command for your platform to build and install the app, then open the installed **Kratos Admin** app. For later JavaScript-only development sessions, start Metro with:

```bash
npm start
```

This runs `expo start --dev-client`. Connect using the installed Kratos Admin development client, rather than Expo Go. Rebuild with `npm run ios` or `npm run android` whenever native dependencies change. If the missing-module error occurs in an older development client, rebuild and install it with the current dependencies.

If an iOS Hermes or React Native Dependencies build script reports that a Node executable no longer exists, check `ios/.xcode.env.local`. This local file overrides `ios/.xcode.env` and can retain an obsolete Node version after an upgrade. Set `NODE_BINARY` to a valid absolute path; for Apple Silicon Homebrew installations, use `export NODE_BINARY=/opt/homebrew/bin/node` so it follows Homebrew's stable symlink. Then rerun the build.

> **Important:** the two unflagged `npx expo run:* --device` commands do not install an OTA-capable production app. Use them while developing, but use the Release commands below for the one-time installation on internal phones. Production EAS updates will then apply to those Release installations.

## Install the OTA-capable app on internal phones

Install a Release build once on every device. Release mode embeds the production update channel and bundled JavaScript:

```bash
npm run android:release
npm run ios:release
```

These expand to:

```bash
npx expo run:android --device --variant release
npx expo run:ios --device --configuration Release
```

iOS device installation still requires the appropriate Apple development team/provisioning selection. Android release signing uses the locally generated signing configuration unless you replace it with your internal production keystore.

## Publish an OTA update

After changing only JavaScript/TypeScript or bundled assets:

```bash
npm run update:production -- --message "Describe the update"
```

This publishes with the current EAS CLI (the shorter `eas update ...` form is equivalent when EAS CLI is installed globally):

```bash
npx eas-cli@latest update --channel production --environment production
```

On launch, the app checks the `production` channel. It downloads an available compatible update in the background and applies it on the next restart. Force-close and reopen twice when manually verifying a new update.

Changes to native dependencies, Expo plugins, permissions, bundle/package identifiers, or the app version/runtime require a new Release installation; EAS Update cannot replace native code.

## Validation

```bash
npm run lint
npm run typecheck
npm test
npm run doctor
npx expo export --platform android
npx expo export --platform ios
```

This repository has also been verified locally with Xcode 26.2. It includes an idempotent post-install patch for an Xcode 26.2 Swift 6 inference issue in `expo-modules-jsi@57.0.4`. The script refuses to patch if the upstream source changes, so a future Expo upgrade fails visibly instead of silently modifying unknown code.
