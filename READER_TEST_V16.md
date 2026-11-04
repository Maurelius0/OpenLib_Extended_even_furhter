# Reader Test v16 APK

Includes the Library / In Progress / Completed categories and automatic refresh
after downloads, preserving v14 EPUB link fixes and v15 image zoom behavior.
Source tree: commit f056632633d0bc872183841a1ce7012d0812c18e.

Artifact: Openlib-Reader-Test-v16.apk (44,671,654 bytes).
SHA-256: 56262568158702017c94426236c749208916d352a53169967545b2d99af97cb5.

## Build and update compatibility

Rebuilt the arm64 release Dart AOT library and Flutter asset bundle using Flutter
3.47.2 (engine a804b261645ef8c13eb3d5c44a5c2fb0340c5539). The matching engine
library and generated native assets are packaged with that bundle. Engine debug
sections were stripped; all allocated sections, addresses and data were checked
against the SDK original after stripping. The original Android DEX, resources,
manifest and JNI bridge are retained from the verified v13 base APK
(afb5f065566f8388ce3a139acd43c9c7777e58a46bed53640d117b2b2ddc9d38).
Android project files and dependency locks have not changed since that base.

As in the previous payload-only test updates, Android's internal version remains
1.0.11 / code 14; v16 identifies this distributed test artifact. The app ID is
still dev.wath.openlibextended.readertest. It is signed with the existing private
test key, whose certificate SHA-256 is
032279ab78112bdd3bf49a31721f3cbb81f2771dddac5a57e5c82312837f38cf.
Signing material is excluded from this repository.

## Checks

- All 31 library and localization regressions pass on this source tree.
- Earlier download, image, EPUB-resource, reader-shell and PDF checks passed.
- Targeted Dart analysis is clean.
- Every rebuilt Flutter payload file was compared byte-for-byte with the APK.
- APK signatures verify under v2 and v3, with the same certificate as the base.
- zipalign verifies 16 KB native-library alignment; the rebuilt AOT ELF supports
  16 KB page sizes.
- Package ID, SDK levels and retained manifest identity were inspected.

The APK was not installed or launched on a physical Pixel or Android emulator.
Install over the existing Reader Test app to retain its local data.
The APK is distributed as a saved download; the GitHub v13 release is unchanged.
