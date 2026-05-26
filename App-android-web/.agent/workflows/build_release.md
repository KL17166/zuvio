---
description: How to build the Flutter app for release with code obfuscation
---

# Build Release APK (Obfuscated)

This workflow produces a release APK with Dart code obfuscation enabled,
making reverse engineering significantly harder.

## Steps

1. Navigate to the Flutter project root:
```
cd c:\Users\kl\Documents\Consorcio\App-android-web
```

// turbo
2. Clean previous build artifacts:
```
flutter clean
```

// turbo
3. Get dependencies:
```
flutter pub get
```

4. Build the release APK with obfuscation:
```
flutter build apk --release --obfuscate --split-debug-info=./debug-info/
```

> **Important Notes:**
> - The `--obfuscate` flag renames all Dart classes, functions, and variables to meaningless names (`a`, `b`, `c1`...)
> - `--split-debug-info` saves the symbol map to `debug-info/` — **keep this for crash reports** (Crashlytics, Sentry)
> - The `debug-info/` directory should NOT be committed to git or included in the APK
> - **Before release**, update `security_service.dart`:
>   - Set `isProd: true` in the TalsecConfig
>   - Replace `DUMMY_HASH_FOR_DEV_REPLACE_IN_PROD` with the real signing certificate SHA-256

5. The APK will be at: `build/app/outputs/flutter-apk/app-release.apk`

// turbo-all
