# Building the apps

## What you need on your computer
- Flutter SDK + Android Studio (Android SDK, accepted licences): run `flutter doctor` until it is green.
- For iPhone builds: a Mac with Xcode and an Apple Developer account.
- Your backend already deployed over HTTPS (DEPLOY.md), and the Firebase `google-services.json` for the partner app (README > Push notifications).

## Android, one command
```
API_URL=https://api.yourdomain.com ORG=com.yourcompany bash scripts/build-apps.sh
```
First run: creates the Android/iOS project folders, adds the permissions, app names and minimum Android version, then builds.
Output in `dist/`: `talkory_user.apk`, `talkory_partner.apk` (install on a phone to test) and the `.aab` files (upload to Google Play).
`ORG` becomes the app ids (e.g. `com.yourcompany.talkory_user`). Choose it once: it must match your Firebase app and cannot change after publishing.
Test on a connected phone first: `cd apps/talkory_user && flutter run --dart-define=API_URL=https://api.yourdomain.com`

## Signing key (do this once, for all three apps)

Until this is set up, every build is signed with a throwaway key: testers must uninstall the old
app before installing a new one, and Google Play will not accept the upload at all.

Make the key (anywhere with Docker or Java, the VPS included):
```
bash scripts/make-signing-key.sh
```
It asks for one password and writes `talkory-upload.jks` plus `talkory-upload.jks.base64`.

**Back up the .jks file and its password.** If you lose them you can never update the apps on
Google Play again under the same listing. Never commit them, and never paste them into a chat.

Then add four repository secrets at
*GitHub > Settings > Secrets and variables > Actions*:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the whole contents of `talkory-upload.jks.base64` |
| `ANDROID_KEYSTORE_PASSWORD` | the password you chose |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | the same password |

From then on every "Build Android apps" run is signed with that key, and new versions install
over old ones. The key only ever exists in those secrets and in your backup, never in the repo.

Each run also sets the Android version code from the run number, so uploads to Google Play always
count upwards. Tick **Also build the .aab files** in the workflow when you need the Play upload
files; leave it off for ordinary APK testing, which is faster.

Building on your own machine instead of GitHub: set `TALKORY_KEYSTORE` to the full path of the
.jks, plus `TALKORY_KEYSTORE_PASSWORD`, `TALKORY_KEY_ALIAS` and `TALKORY_KEY_PASSWORD`, then run
`scripts/build-apps.sh` as usual.

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

## Firebase for the server (so the partner phone rings)
Besides the four app values above, the backend needs a service-account key: Firebase console > Project settings > Service accounts > Generate new private key (downloads a .json file).
On Windows PowerShell, put it on the clipboard as one base64 line (nothing is printed):
`[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\your-key-file.json")) | Set-Clipboard`
Paste it as the environment variable `FIREBASE_SERVICE_ACCOUNT_B64` in Docker Manager and redeploy. Treat that value like a password: never put it in GitHub or chat.
