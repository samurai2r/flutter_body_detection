## 0.0.4 - 2024-05-17

### Breaking Changes
- Updated minimum Flutter SDK constraint to 3.0.0
- Updated minimum Dart SDK constraint to 2.17.0

### Updates
- Updated Android dependencies:
  - Updated MLKit dependencies to beta versions (pose-detection-accurate:18.0.0-beta3, segmentation-selfie:16.0.0-beta4)
  - Updated CameraX to version 1.3.0
  - Updated Lifecycle to version 2.7.0
- Updated iOS dependencies:
  - Maintained GoogleMLKit dependencies at version 3.2.0 for compatibility
- Fixed compatibility with Flutter 3.29.3
- Added proper namespace configuration for Android
- Added CAMERA permission to Android manifest
- Fixed lifecycle handling in CameraSession.kt
- Updated example app to use newer plugin versions

## 0.0.3

* Fixed an issue which prevented the library to compile on Android.

## 0.0.2

* Fixed example app screenshots links in the README file.

## 0.0.1

* Initial Open Source release.
