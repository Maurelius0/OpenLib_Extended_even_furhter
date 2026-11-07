# Automated Android builds

The project has a GitHub Actions workflow at
[.github/workflows/reader-android.yml](.github/workflows/reader-android.yml).

## What runs

Every relevant push to `main` and every manual **Run workflow** invocation
sets up Java 17, Android API 36 and **Flutter 3.47.2**, installs locked
dependencies, runs targeted reader regression tests and compiles an arm64
Android debug APK to catch build errors.

The debug APK is **not** published as an update. Its ephemeral CI signing
certificate does not match the certificate of previously installed reader
test APKs. Do **not** uninstall the installed app just to switch keys,
because doing so can erase the local library and reading progress.

## Signed updates — required once

To produce an APK that can be installed over the existing reader test app,
recover the **original private keystore and credentials** used for V13–V16.
GitHub Actions cannot derive the signing key from a compiled APK.

The original development keystore was recovered from an older private
project archive and its certificate fingerprint matches V13–V16. Preserve
an offline copy of it.

Configure **one repository Actions secret** in GitHub **Settings > Secrets
and variables > Actions > New repository secret** (never commit its value):

- Name: `READER_ANDROID_KEYSTORE_BASE64`
- Value: one-line base64 encoding of the original keystore
  (`base64 -w 0 reader-original-test-signing.jks` on Linux)

The existing test key uses the standard Android debug-key credentials:
alias `androiddebugkey`, keystore/key passwords `android`. These values
are not secret; the **private keystore file** is. The workflow checks the
certificate fingerprint before it uses the key. Do not replace the keystore
with one created by a new Android SDK installation.

When those are present, the workflow verifies the key certificate SHA-256
against the historical test build's certificate:

`032279ab78112bdd3bf49a31721f3cbb81f2771dddac5a57e5c82312837f38cf`

It refuses to sign with any other key, then creates and verifies a release
APK and uploads it as a private-to-workflow GitHub Actions artifact for
download. Android versionCode is automatically greater than the old value 14.
No GitHub Release is automatically published until the APK is reviewed.

## Distribution filenames

Successful signed builds are uploaded under the familiar name
`Openlib-Reader-Test-v18` and contain
`Openlib-Reader-Test-v18.apk`, instead of Flutter's generic `app-release.apk`.
GitHub Actions packages artifacts in a ZIP when downloaded; extract the ZIP on
Android to get the APK. The ZIP name and the actual APK filename are separate
from the APK's Android application ID and signing certificate.

The reader milestone number is defined by `READER_TEST_VERSION` in the
workflow. Bump it for the next user-facing milestone (v19, v20, etc.) rather
than calling every CI run a new functional version. Android's internal
`versionCode` remains automatically increasing per workflow run to permit
in-place installation; the filename does not determine upgrade compatibility.


If the old keystore is irretrievably lost, an in-place Android update using
the same app package is not possible. Plan and verify an export/import of the
reader's local data before considering a differently signed replacement.
Do not generate a new keystore and silently substitute it.

## Review after first run

Open **Actions > Reader Android build** on GitHub to check the run's status,
test results and build logs. After configuring the original key, use **Run
workflow** and download the signed artifact from the successful run.
The workflow does not install or run the APK on a physical Pixel.
