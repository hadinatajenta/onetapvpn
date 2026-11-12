# Changelog

All notable changes to OneTapVPN are documented here.

## 1.1.0 - 2026-11-12

### Added

- Camera QR scanning for TOTP setup with a live camera preview.
- Provisioning URI parsing that fills the secret, digits, period, and algorithm.
- Custom scanned period values in the period picker.
- Camera permission states with retry and a shortcut to System Settings.
- App icon pipeline from `onetapicon.jpeg` to a full macOS `.icns` asset.
- Clearer README documentation, project layout, limitations, and troubleshooting.

### Changed

- QR detection uses Vision barcode detection instead of `AVCaptureMetadataOutput`, which is unreliable on macOS.
- The TOTP parser is shared between code generation and QR provisioning instead of duplicating URI parsing.

### Fixed

- The app icon no longer appears smaller than other Dock icons because of dark padding in the source image.
- Invalid and unsupported QR codes are rejected without changing the saved form values.

## 1.0.0 - 2026-11-02

### Added

- Initial macOS menu bar app for the official GlobalProtect client.
- Local TOTP generation and Keychain credential storage.
- Accessibility automation for the GlobalProtect sign-in window.
- Connection status monitoring, auto-reconnect, and launch at login.
- Build, install, signing, and uninstall scripts.
