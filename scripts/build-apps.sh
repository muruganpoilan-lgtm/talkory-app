#!/usr/bin/env bash
# Builds both Talkory apps (installable APK + Play Store bundle). Run from anywhere; needs the Flutter SDK + Android SDK.
# Set APK_ONLY=1 to skip the Play Store bundle. Output: dist/Talkory.apk and "dist/Talkory Partner.apk".
# Usage:  API_URL=https://api.yourdomain.com [SENTRY_DSN=...] [ORG=com.yourcompany] bash scripts/build-apps.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${API_URL:?Set API_URL, e.g. API_URL=https://api.yourdomain.com}"
ORG="${ORG:-com.example}"
SENTRY_DSN="${SENTRY_DSN:-}"
SKIP_FLUTTER="${SKIP_FLUTTER:-}" # set to 1 to only apply the file patches (used for testing the script)

if [[ -z "$SKIP_FLUTTER" ]] && ! command -v flutter >/dev/null; then
  echo "Flutter SDK not found. Install it (https://docs.flutter.dev/get-started/install), run 'flutter doctor', then try again."; exit 1
fi
[[ "$API_URL" == https://* ]] || echo "WARNING: API_URL is not https. Release Android builds refuse plain http."

# Adds permissions, app name and minSdk (Android) and usage texts + background modes (iOS). Safe to run repeatedly.
patch_platforms() { # app_dir label "PERMISSIONS" "ios background modes"
python3 - "$@" <<'PY'
import os, re, sys, plistlib
d, label, perms, modes = sys.argv[1], sys.argv[2], sys.argv[3].split(), sys.argv[4].split()

m = os.path.join(d, 'android/app/src/main/AndroidManifest.xml')
if os.path.exists(m):
    s = open(m).read()
    add = ''.join(f'    <uses-permission android:name="android.permission.{p}"/>\n' for p in perms if f'android.permission.{p}"' not in s)
    if add: s = s.replace('<application', add + '    <application', 1)
    s = re.sub(r'android:label="[^"]*"', f'android:label="{label}"', s, count=1)
    open(m, 'w').write(s)

for name in ('android/app/build.gradle.kts', 'android/app/build.gradle'):  # Firebase/Agora need a newer minimum than Flutter's default
    g = os.path.join(d, name)
    if os.path.exists(g):
        s = open(g).read()
        s = re.sub(r'minSdk(Version)?\s*=?\s*(flutter\.minSdkVersion|\d+)', 'minSdk = 23' if name.endswith('.kts') else 'minSdkVersion 23', s)
        open(g, 'w').write(s)

pl = os.path.join(d, 'ios/Runner/Info.plist')
if os.path.exists(pl):
    with open(pl, 'rb') as f: data = plistlib.load(f)
    data.setdefault('NSMicrophoneUsageDescription', 'The microphone is used so you can talk during calls.')
    data.setdefault('NSCameraUsageDescription', 'The camera is used to take your profile and verification photos.')
    data.setdefault('NSPhotoLibraryUsageDescription', 'Choose a photo for your profile or verification.')
    data['CFBundleDisplayName'] = label
    if modes: data['UIBackgroundModes'] = sorted(set(data.get('UIBackgroundModes', [])) | set(modes))
    with open(pl, 'wb') as f: plistlib.dump(data, f)
PY
}

# Some plugins (e.g. Agora) are compiled against an old Android SDK (31) while their androidx dependencies need 33/34+,
# which fails the build at "checkReleaseAarMetadata". This Gradle init script raises compileSdk to 36 for every plugin module.
write_gradle_init() {
  local d="${GRADLE_USER_HOME:-$HOME/.gradle}/init.d"
  mkdir -p "$d"
  cat > "$d/talkory-compilesdk.gradle" <<'GRADLE_END'
allprojects {
    afterEvaluate { p ->
        def android = p.extensions.findByName('android')
        if (android != null && p.name != 'app') {
            try {
                android.compileSdkVersion(36)
            } catch (Throwable ignored) {
                try { android.compileSdk = 36 } catch (Throwable ignored2) { }
            }
        }
    }
}
GRADLE_END
}
[[ -n "$SKIP_FLUTTER" ]] || write_gradle_init

build_app() { # project_name label "PERMISSIONS" "ios modes" needs_firebase(yes|no)
  local name="$1" label="$2" perms="$3" modes="$4" fb="$5" dir="apps/$1"
  echo; echo "=== $label ==="
  if [[ -z "$SKIP_FLUTTER" && ! -d "$dir/android" ]]; then
    (cd "$dir" && flutter create . --org "$ORG" --project-name "$name" --platforms=android,ios && rm -f test/widget_test.dart)
  fi
  patch_platforms "$dir" "$label" "$perms" "$modes"
  if [[ "$fb" == yes && -z "$SKIP_FLUTTER" && -z "${FIREBASE_API_KEY:-}" && ! -f "$dir/android/app/google-services.json" ]]; then
    echo "NOTE: Firebase is not configured, so $label will work but will not ring for incoming calls (see BUILD.md > Firebase)."
  fi
  [[ -f "$dir/android/key.properties" ]] || echo "NOTE: no android/key.properties, so this build is debug-signed: fine for testing, not for Google Play (see BUILD.md)."
  [[ -n "$SKIP_FLUTTER" ]] && return 0
  local defs=(--dart-define=API_URL="$API_URL" --dart-define=SENTRY_DSN="$SENTRY_DSN"
    --dart-define=FIREBASE_API_KEY="${FIREBASE_API_KEY:-}" --dart-define=FIREBASE_APP_ID="${FIREBASE_APP_ID:-}"
    --dart-define=FIREBASE_SENDER_ID="${FIREBASE_SENDER_ID:-}" --dart-define=FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-}")
  (cd "$dir" && flutter pub get && flutter build apk --release "${defs[@]}" && { [[ -n "${APK_ONLY:-}" ]] || flutter build appbundle --release "${defs[@]}"; })
  mkdir -p dist
  cp "$dir/build/app/outputs/flutter-apk/app-release.apk" "dist/$label.apk"
  [[ -f "$dir/build/app/outputs/bundle/release/app-release.aab" ]] && cp "$dir/build/app/outputs/bundle/release/app-release.aab" "dist/$label.aab" || true
}

COMMON="INTERNET ACCESS_NETWORK_STATE RECORD_AUDIO MODIFY_AUDIO_SETTINGS BLUETOOTH_CONNECT"
build_app talkory_user    "Talkory"         "$COMMON"                                                                                    "audio"                          no
build_app talkory_partner "Talkory Partner" "$COMMON POST_NOTIFICATIONS USE_FULL_SCREEN_INTENT FOREGROUND_SERVICE FOREGROUND_SERVICE_MICROPHONE WAKE_LOCK VIBRATE CAMERA" "audio remote-notification voip" yes

echo; echo "Done. dist/*.apk installs on a phone for testing; dist/*.aab is what you upload to Google Play."
echo "iPhone builds need a Mac: see BUILD.md and IOS_VOIP.md."
