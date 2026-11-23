# Tandem (mobile)

Flutter app that connects your phone and PC over local Wi-Fi. Direct, private, encrypted companion without cloud services.

## Run it
Requirements: Flutter 3.38 or newer (stable), Android Studio or the Android SDK with JDK 17+.

```
flutter pub get
flutter run          # with a real phone connected
```
Use a real phone: it needs a camera for pairing and must be on the same Wi-Fi as your PC.
`flutter pub get` also creates `android/local.properties` and the Gradle wrapper files, which are not committed.

## Use it
1. Start the Tandem desktop app. On first run it shows a QR code.
2. Open Tandem on the phone and scan it.
3. In any app (Gallery, Files, Chrome, WhatsApp...) tap Share and choose Tandem.

## Project layout
```
lib/
  main.dart            app entry, theme, lifecycle
  app_state.dart       state shared by all screens
  uploader.dart        queue, sending, retry (no UI; also used in the background)
  pc_client.dart       HTTPS client pinned to the PC's certificate, mDNS lookup
  background.dart      WorkManager periodic retry
  share_intake.dart    receives shares from other apps
  db.dart storage.dart models.dart util.dart app_scope.dart
  screens/             pair, home, queue, settings, share sheet, remote, pc_files, launcher
android/               Gradle project (applicationId com.tandem.app)
ios/                   Xcode project (bundle id com.tandem.app)
test/models_test.dart  unit tests (flutter test)
```

## How it works
- **Pairing:** the QR code carries the PC's address, a one-time secret and its certificate fingerprint. The phone only trusts a certificate with that exact SHA-256 (system CAs are disabled for this connection). The access token is stored in secure storage.
- **Finding the PC:** it tries the last known address, then looks for `_tandem._tcp` (and `_phonesaves._tcp`) on the network and matches the advertised fingerprint, so it still works after the PC's IP changes.
- **Queue:** everything shared is copied into app storage and recorded in SQLite before sending. If the PC is unreachable it stays queued and is retried when the app opens, when Wi-Fi connects, and about every 15 minutes in the background.
- **Shared text:** a link in it is sent as a link; otherwise it is saved on the PC as a `.txt` file.

## App updates
- **Phone app (Android):** Settings checks the public `tandem-phone` GitHub release feed, verifies the downloaded APK's SHA-256, then opens Android's installer. Android verifies the APK signature against the installed app before replacing it. The first update from versions before 1.0.2 requires manually installing the 1.0.2 APK once because older builds do not include the phone updater.
- To publish an Android update, increment `version` in `pubspec.yaml` (both the human version and build number), commit and push to the Tandem phone GitHub repository, then run `./publish-release.ps1` on the Windows release machine. The script builds with the established local signing key, verifies its certificate fingerprint, creates the GitHub release, and uploads the APK plus the `latest.json` feed consumed by installed apps. It stops if the signing key differs, because Android cannot install an update signed by a different key.
- The established signing key is the release machine's Android debug keystore (`%USERPROFILE%\.android\debug.keystore`). Keep that file backed up and private; use the same machine/key for future Android releases. The script never uploads the signing key.
- **Desktop app:** its separate updater and release process are documented in the desktop repository. iOS builds use Apple's App Store distribution path; no iOS release feed is configured.

## Changing the app id
Replace `com.tandem.app` in `android/app/build.gradle.kts` (`namespace` and `applicationId`), move `android/app/src/main/kotlin/com/tandem/app/MainActivity.kt` to the matching folder and update its `package` line. For iOS change the bundle identifier in Xcode.

## Limits
- **iOS share menu:** the iOS project is included and the app code runs, but showing Tandem in the iOS Share menu needs a Share Extension target, which has to be added in Xcode (see the `receive_sharing_intent` README). Android is complete.
- No manual pairing entry; the QR code is the only way to pair.
- Android decides when background retry runs; it is best effort.
