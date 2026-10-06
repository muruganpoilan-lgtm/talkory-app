# Building the apps

## What you need on your computer
- Flutter SDK + Android Studio (Android SDK, accepted licences): run `flutter doctor` until it is green.
- For iPhone builds: a Mac with Xcode and an Apple Developer account.
- Your backend already deployed over HTTPS (DEPLOY.md), and the Firebase `google-services.json` for the partner app (README > Push notifications).

## Android, one command
```
API_URL=https://api.yourdomain.com SENTRY_DSN=<optional> ORG=com.yourcompany bash scripts/build-apps.sh
```
First run: creates the Android/iOS project folders, adds the permissions, app names and minimum Android version, then builds.
Output in `dist/`: `talkory_user.apk`, `talkory_partner.apk` (install on a phone to test) and the `.aab` files (upload to Google Play).
`ORG` becomes the app ids (e.g. `com.yourcompany.talkory_user`). Choose it once: it must match your Firebase app and cannot change after publishing.
Test on a connected phone first: `cd apps/talkory_user && flutter run --dart-define=API_URL=https://api.yourdomain.com`

## Signing for Google Play (once per app)
```
keytool -genkey -v -keystore ~/talkory-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
Keep that file and its passwords safe and backed up: losing them means you cannot update the app as before.
Create `apps/<app>/android/key.properties`:
```
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/full/path/to/talkory-upload.jks
```
Then in `android/app/build.gradle.kts` (follow Flutter's "Build and release an Android app" > Signing page for your Flutter version) read that file and
point `signingConfigs.release` and `buildTypes.release` at it. Rebuild with the script.

## iPhone (on a Mac)
1. `ORG=... bash scripts/build-apps.sh` has already created `ios/` and added the usage texts and background modes. Run `flutter pub get` in each app.
2. Open `apps/<app>/ios/Runner.xcworkspace` in Xcode: set your Team and bundle id; add *Push Notifications*; for the partner app also *Background Modes*.
3. Partner app: finish IOS_VOIP.md (AppDelegate step, APNs key). Add `GoogleService-Info.plist` from Firebase to Runner.
4. `flutter build ipa --dart-define=API_URL=https://api.yourdomain.com`, then upload from Xcode (Organizer) to TestFlight.

## Before you publish
- App icons: add the `flutter_launcher_icons` package and your logo (the default is the Flutter logo).
- Version: bump `version:` in each `pubspec.yaml` for every upload.
- Store listings need: your privacy policy URL (`/legal/privacy`), account deletion URL (`/legal/delete-account`), and honest data-safety answers (phone number, voice, photos, payment info).
- Work through `TEST_PLAN.md` on real phones using the `.apk` files first.

## Build in the cloud with GitHub (no Flutter on your computer)
1. Create a **private** GitHub repository and push the **contents** of this `talkory` folder as the repository root (so `.github/workflows` sits at the top). Never commit `.env` files or `firebase-service-account.json` (they are git-ignored).
2. Optional secrets (repo > Settings > Secrets and variables > Actions): `SENTRY_DSN` and the four Firebase values below.
3. Repo > **Actions** > "Build Android apps" > **Run workflow** > enter your backend URL > wait 10 to 15 minutes.
4. Open the finished run, download the **talkory-apks** artifact, unzip it: `Talkory.apk` and `Talkory Partner.apk`. Copy them to the phones and install.
If the run fails, open the red step, copy the last 40 lines of its log and send them to me.

## Firebase without google-services.json (what the cloud build uses)
Without Firebase the partner app still installs and works (sign-up, profile, KYC, earnings) but phones will not ring for incoming calls.
To enable calls, add an Android app in the Firebase console (package name = `<org>.talkory_partner`, default `com.talkory.talkory_partner`) and set these as GitHub secrets
(or as environment variables when running `scripts/build-apps.sh`):
- `FIREBASE_PROJECT_ID`: Project settings > General > Project ID
- `FIREBASE_SENDER_ID`: the same page, "Project number"
- `FIREBASE_APP_ID`: under "Your apps" > the Android app > App ID (looks like `1:1234567890:android:abc123`)
- `FIREBASE_API_KEY`: the "current_key" value inside the downloaded google-services.json (or Google Cloud Console > Credentials)
