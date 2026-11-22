#!/usr/bin/env bash
# Makes the one signing key Talkory uses for every Android release, from now on, forever.
#
#   bash scripts/make-signing-key.sh
#
# Needs either keytool (from Java) or Docker. Writes two files into the folder you run it in:
#   talkory-upload.jks         the key itself. BACK THIS UP. Losing it means you can never update
#                              the app on Google Play again: you would have to publish a new listing.
#   talkory-upload.jks.base64  the same key as text, to paste into the GitHub secret.
#
# Never commit either file, never email them, and never paste them into a chat.
set -euo pipefail

OUT="${OUT:-talkory-upload.jks}"
ALIAS="${ALIAS:-upload}"

if [[ -f "$OUT" ]]; then
  echo "$OUT already exists here. Move it aside first, or you will overwrite the key you are already using."
  exit 1
fi

echo "This makes the signing key for the Talkory Android apps."
echo "Choose one password and keep it somewhere safe: you need it for every release."
echo
read -r -s -p "Password for the key (at least 6 characters): " PASS; echo
read -r -s -p "Type it again: " PASS2; echo
[[ "$PASS" == "$PASS2" ]] || { echo "The two passwords are different. Nothing was made; run it again."; exit 1; }
[[ ${#PASS} -ge 6 ]] || { echo "Too short: Android needs at least 6 characters."; exit 1; }

DNAME="CN=Talkory, OU=Talkory, O=Talkory, L=Chennai, ST=Tamil Nadu, C=IN"
ARGS=(-genkeypair -v -keystore "$OUT" -alias "$ALIAS" -keyalg RSA -keysize 2048
      -validity 10000 -storetype PKCS12 -dname "$DNAME"
      -storepass "$PASS" -keypass "$PASS")

if command -v keytool >/dev/null 2>&1; then
  keytool "${ARGS[@]}"
elif command -v docker >/dev/null 2>&1; then
  docker run --rm -v "$PWD":/work -w /work eclipse-temurin:17-jdk keytool "${ARGS[@]}"
  # the container writes as root: hand the file back
  [[ "$(id -u)" == 0 ]] || sudo chown "$(id -u):$(id -g)" "$OUT" 2>/dev/null || true
else
  echo "Neither keytool nor docker is available here. Run this on the VPS, which has Docker."
  exit 1
fi

base64 -w0 "$OUT" > "$OUT.base64" 2>/dev/null || base64 "$OUT" | tr -d '\n' > "$OUT.base64"
chmod 600 "$OUT" "$OUT.base64"

cat <<EOF

Done. Two files are here: $(pwd)

Next, add four secrets at:
  GitHub > your repository > Settings > Secrets and variables > Actions > New repository secret

  ANDROID_KEYSTORE_BASE64    the whole contents of $OUT.base64
  ANDROID_KEYSTORE_PASSWORD  the password you just typed
  ANDROID_KEY_ALIAS          $ALIAS
  ANDROID_KEY_PASSWORD       the same password again

To read the base64 out:   cat $OUT.base64
It is one very long line. Copy all of it, with no spaces or line breaks.

Then download $OUT and keep a backup somewhere safe and private.
After that, every "Build Android apps" run is signed with this key.
EOF
