# Deployment Guide

Last verified locally: 2026-03-09

This document separates local/device deployment from store deployment. Store
distribution always needs platform account setup, metadata, and signing assets that
must stay out of git.

## Current Readiness

### iOS

- Local device deployment: ready
- TestFlight / App Store deployment: partially ready

Current repository state:

- Release device build succeeds locally with Xcode.
- Bundle ID is `org.duckdns.lhfser.AIMoney`.
- The project is still configured for automatic signing with an Apple Development
  identity, so store upload still depends on App Store Connect setup and
  distribution signing on your machine.

### Android

- Local debug deployment: ready after Android build fixes are merged
- Google Play internal / closed / production deployment: partially ready

Current repository state:

- Debug build and unit tests pass locally.
- The project supports release signing via local `android/keystore.properties`.
- A Play-ready signed bundle still requires your upload keystore and Play Console
  app setup.

## iOS Deployment

### Deploy to your own iPhone from Xcode

Prerequisites:

- Xcode installed
- Your iPhone trusted and connected
- Your Apple account selected in Xcode signing

Steps:

1. Open `AI 記帳.xcodeproj` in Xcode.
2. Select the `AI 記帳` scheme and your iPhone as the run destination.
3. In Signing & Capabilities, confirm the Team matches your Apple account.
4. Build and run with `Cmd + R`.

If Xcode asks to trust the developer on the phone, open Settings > General > VPN &
Device Management and trust the profile.

### Deploy to TestFlight / App Store

Prerequisites:

- Apple Developer Program membership
- App Store Connect app record created before upload
- Distribution signing assets available to Xcode
- Version and build numbers bumped before each upload

Steps:

1. In App Store Connect, create the iOS app record for bundle ID
   `org.duckdns.lhfser.AIMoney`.
2. In Xcode, update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
3. Select `Any iOS Device` or `generic/platform=iOS`.
4. Use Product > Archive.
5. In Organizer, choose Distribute App > App Store Connect > Upload.
6. Wait for build processing in App Store Connect.
7. For TestFlight, add internal or external testers.
8. For App Store release, fill in metadata, screenshots, privacy answers, export
   compliance answers, then submit for review.

## Android Deployment

### Deploy locally to emulator or USB device

Prerequisites:

- Android SDK installed
- `android/local.properties` points to `sdk.dir`

Steps:

1. Build debug APK:

```bash
cd android
./gradlew :app:assembleDebug
```

2. Install to a connected device or running emulator:

```bash
cd android
./gradlew :app:installDebug
```

### Deploy to Google Play

Prerequisites:

- Google Play developer account
- Upload keystore created and stored outside git
- Local `android/keystore.properties` created from
  `android/keystore.properties.example`

Steps:

1. Create or locate your upload keystore.
2. Fill in `android/keystore.properties` with the keystore path and passwords.
3. Build the release bundle:

```bash
cd android
./gradlew :app:bundleRelease
```

4. Open Play Console and create the app using package name
   `org.duckdns.lhfser.aiaccounting`.
5. Start with Internal testing, upload the generated `.aab`, and complete the
   required App content forms.
6. After testing, promote the same artifact to Closed testing or Production.

## Official References

- Apple App Store Connect workflow:
  https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-workflow/
- Apple upload builds:
  https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- Apple export compliance:
  https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation
- Apple membership and distribution overview:
  https://developer.apple.com/support/compare-memberships/
- Android app signing:
  https://developer.android.com/guide/publishing/app-signing.html
- Google Play release tracks:
  https://support.google.com/googleplay/android-developer/answer/9859348
- Google Play testing tracks:
  https://support.google.com/googleplay/android-developer/answer/9845334
- Google Play internal app sharing:
  https://support.google.com/googleplay/android-developer/answer/9844679
