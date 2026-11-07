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

Configure these repository **Actions secrets** in GitHub Settings >
Secrets and variables > Actions (never commit or paste the credentials):

- `READER_ANDROID_KEYSTORE_BASE64`: base64 encoding of the binary keystore,
  generated with `base64 -w 0 your-original-keystore.jks` on Linux
- `READER_ANDROID_STORE_PASSWORD`: keystore password
- `READER_ANDROID_KEY_ALIAS`: original signing key alias
- `READER_ANDROID_KEY_PASSWORD`: key password

When those are present, the workflow verifies the key certificate SHA-256
against the historical test build's certificate:

`032279ab78112bdd3bf49a31721f3cbb81f2771dddac5a57e5c82312837f38cf`

It refuses to sign with any other key, then creates and verifies a release
APK and uploads it as a private-to-workflow GitHub Actions artifact for
download. Android versionCode is automatically greater than the old value 14.
No GitHub Release is automatically published until the APK is reviewed.

If the old keystore is irretrievably lost, an in-place Android update using
the same app package is not possible. Plan and verify an export/import of the
reader's local data before considering a differently signed replacement.
Do not generate a new keystore and silently substitute it.

## Review after first run

Open **Actions > Reader Android build** on GitHub to check the run's status,
test results and build logs. After configuring the original key, use **Run
workflow** and download the signed artifact from the successful run.
The workflow does not install or run the APK on a physical Pixel.
