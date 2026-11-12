# OneTapVPN

OneTapVPN is a macOS menu bar app for the official Palo Alto Networks GlobalProtect client. It generates the TOTP code locally and fills the GlobalProtect sign-in form, so a normal connection takes one click.

It does not include, replace, or modify GlobalProtect. It automates the client you already have.

## Features

- One-click connect and disconnect from the menu bar or the Dock menu.
- TOTP generated locally with SHA1, SHA256, or SHA512, 6 to 8 digits, and a 30, 60, or custom period.
- QR code scanning with the Mac camera, or manual entry of a base32 secret or an `otpauth://` URI.
- Credentials stored in the macOS Keychain instead of a plain text file.
- Connection status monitoring, auto-reconnect, and launch at login.
- Accessibility automation for the GlobalProtect sign-in window.
- No third-party dependencies and no network code in the app.

## Requirements

- macOS 13 Ventura or later.
- The official GlobalProtect client installed and able to connect manually.
- Xcode Command Line Tools (`xcode-select --install`).
- A camera for QR scanning. Manual entry works without one.
- Admin access only when installing to `/Applications`.

The project builds with Swift 6.2 in Swift 5 language mode.

## Quick start

Create the local signing identity once:

```sh
bash scripts/setup-signing.sh
```

Build and install for the current user:

```sh
bash scripts/install.sh
```

Then open Settings from the menu bar icon and complete the connection fields. Grant Accessibility and Camera access when macOS asks.

The local signing identity is important. macOS ties Accessibility and Camera permissions to the app's code signature, so a stable identity keeps those permissions across rebuilds. Without it, the build falls back to an ad-hoc signature and macOS may ask again after every rebuild.

## Build

Create the local signing identity once:

```sh
bash scripts/setup-signing.sh
```

Build the app:

```sh
bash scripts/build.sh
```

The bundle is written to `build/OneTapVPN.app`. The script compiles every Swift file under `Sources`, copies `Resources/Info.plist`, embeds `Resources/AppIcon.icns`, and signs the bundle with the local identity. If the identity is missing, the script falls back to an ad-hoc signature and prints a warning.

Run only the compiler check:

```sh
bash scripts/typecheck.sh
```

Run the unit tests:

```sh
bash Tests/run-tests.sh
```

The tests cover Base32 decoding, the RFC 6238 TOTP vectors, URI behavior, and provisioning URI parsing. The current suite has 35 cases.

### App icon

`onetapicon.jpeg` in the repository root is the icon source. Regenerate the macOS icon asset with:

```sh
bash scripts/make-icon.sh
```

The script uses `scripts/render-icon.swift` to trim the dark padding around the artwork, make the corners transparent, and write every size to `Resources/AppIcon.icns`. `scripts/build.sh` embeds that file into the app bundle and generates it automatically when it is missing.

## Install

Install for the current user:

```sh
bash scripts/install.sh
```

This builds the app, installs it to `~/Applications/OneTapVPN.app`, removes the quarantine attribute, and opens it.

Install for every user on the Mac:

```sh
bash scripts/install.sh --system
```

This installs to `/Applications/OneTapVPN.app` and requires an account that can write to `/Applications`.

To build without installing, run `bash scripts/build.sh` and copy `build/OneTapVPN.app` wherever you need it.

## First run

1. Click the OneTapVPN icon in the menu bar and choose Settings. The app also opens Settings automatically on first launch.
2. Enter the portal, username, and password.
3. Enter the TOTP secret, paste a complete `otpauth://` URI, or click Scan QR Code and point the camera at the QR code from your authenticator.
4. Verify that the live code matches the code shown by your authenticator app.
5. Save the settings.
6. Grant Accessibility access in System Settings > Privacy & Security > Accessibility.
7. Click Test Connection and approve the GlobalProtect login if prompted.

The app appears in the menu bar and in the Dock. Click the Dock icon to open Settings, or use the menu bar icon for one-click connect and disconnect.

## QR code scanning

Click Scan QR Code next to the TOTP secret field. The app opens a camera sheet and scans the first QR code it recognizes.

Supported payloads:

- `otpauth://totp/...` provisioning URIs. The scanner fills the secret, digits, period, and algorithm.
- Plain base32 secrets. The scanner fills the secret and keeps the current advanced settings.

Unsupported payloads are reported without changing the form:

- `otpauth-migration://` export codes from Google Authenticator.
- `otpauth://hotp/...` counter-based codes.
- URLs, arbitrary text, and secrets that are not valid base32.

The scanner resumes automatically after an invalid code, so you can scan again without reopening the sheet.

The camera is used only while the scanner sheet is open. Frames are processed on-device with AVFoundation and Vision, are not stored, and are not transmitted. Closing the sheet or detecting a valid code stops the camera session.

Camera permission is requested the first time you open the scanner. If access is denied, the sheet offers Try Again and Open System Settings. If the Mac has no camera, the sheet explains the limitation and manual entry remains available.

## Advanced TOTP settings

The Advanced section controls:

- OTP placement: append or prepend the code to the password.
- OTP separator: optional text between the password and the code.
- Digits: 6, 7, or 8.
- Period: 30 or 60 seconds, plus a scanned custom value when needed.
- Algorithm: SHA1, SHA256, or SHA512.

When the TOTP secret field contains a complete `otpauth://` URI, values in the URI take precedence over the individual controls.

## How it works

- Credentials are stored in the macOS Keychain, not in a plain text file.
- The TOTP code is computed locally from the stored secret.
- The QR scanner reads camera frames with AVFoundation and decodes QR codes with Vision.
- The app uses the macOS Accessibility API to find the official GlobalProtect windows and fill the login form.
- GlobalProtect performs the actual VPN connection and keeps its own configuration.

OneTapVPN does not replace GlobalProtect, bundle its binaries, or change VPN profiles, routes, DNS settings, or certificates.

## Project structure

```text
Sources/App             Menu bar, settings window, VPN controller, QR scanner
Sources/Core            TOTP, Base32, Keychain access, logging
Sources/GlobalProtect   Accessibility automation and status monitoring
Sources/Shared          Models and protocols
Tests                   TOTP and provisioning parser tests
Resources               Info.plist and generated app icon
scripts                 Build, install, signing, icon, and uninstall scripts
```

The build script discovers new Swift files under `Sources` automatically, so no project file needs updating when a source file is added.

## Security and privacy

- The password and TOTP secret are stored in the Keychain and are not written to disk in plain text.
- The app makes no network connections. Only GlobalProtect contacts the VPN gateway.
- The camera is used only to decode the QR code while the scanner sheet is open. Frames are processed in memory and are not stored or transmitted.
- The app does not bundle, install, or modify GlobalProtect.
- Storing the password and TOTP secret together makes two-factor authentication effectively single-factor. Anyone who can read the stored credentials can produce both factors.
- Accessibility permission lets OneTapVPN inspect and control other apps. Grant it only to a build you trust.
- Camera permission lets OneTapVPN read frames while the scanner is open. Revoke it in System Settings when you no longer need QR scanning.
- Check your employer's IT policy before use. Automating a corporate VPN client may be restricted or forbidden.
- The app is signed with a local self-signed code signing identity, not by Apple. The private key stays in `~/.config/onetapvpn/signing` and `~/Library/Keychains/onetapvpn-signing.keychain-db`. The stable identity keeps permissions across rebuilds. Build and install it on the Mac where you use it.
- The repository ignores `.env` files, signing material, private keys, certificates, keychains, build output, and app bundles.

## Troubleshooting

### Accessibility permission is not granted

Open System Settings > Privacy & Security > Accessibility and enable OneTapVPN. If there are several OneTapVPN entries, remove all of them with the minus button, add `~/Applications/OneTapVPN.app` again, and restart OneTapVPN. Use the installed app, not a copy from the build folder. The local signing identity keeps this permission stable across future rebuilds.

### Camera permission is not granted

Open System Settings > Privacy & Security > Camera and enable OneTapVPN. If the app is not listed, open the QR scanner once to trigger the permission request. Without camera access, paste the TOTP secret or `otpauth://` URI instead.

### The scanner reports that no camera is available

Confirm that the Mac has a camera and that no other app is holding it exclusively. Manual entry remains available. On Macs without a camera, use the secret or `otpauth://` URI.

### A QR code is not recognized

Hold the code steady and fill more of the preview with it. Avoid glare and keep the whole code inside the frame. If the code is still not recognized, enter the secret manually.

### The QR code is rejected

OneTapVPN accepts standard TOTP provisioning codes and plain base32 secrets. Google Authenticator export codes (`otpauth-migration://`), HOTP codes, and arbitrary URLs are not supported.

### Login fields are not found

Open GlobalProtect manually and confirm that its sign-in window appears. Portals that require SSO, SAML, or a client certificate may use a flow that OneTapVPN cannot fill. Generate a diagnostic report to see which accessibility elements were found.

### Diagnostic report

The app writes accessibility diagnostics to `~/Library/Logs/OneTapVPN`. Review the report before sharing it because it can contain portal or account text.

### Password changed

Open Settings, enter the new password, and save. The next connection uses the updated password.

### TOTP code mismatch

Confirm that the secret, digits, period, and algorithm match the authenticator entry. Enable automatic date and time on the Mac so the TOTP clock stays in sync. If you scanned a QR code, rescan it or paste the original `otpauth://` URI.

### GlobalProtect updated and the UI changed

A GlobalProtect update can change accessibility labels and break automation. Reopen OneTapVPN and generate a diagnostic report. Supporting a new interface requires updating the accessibility selectors in the source.

### Permissions are requested again after a rebuild

Run `bash scripts/setup-signing.sh` before building, then reinstall the app. The ad-hoc fallback used when the local identity is missing produces a different signature, so macOS treats the new build as a different app for permission purposes.

## Limitations

- TOTP only. HOTP and Google Authenticator migration exports are not supported.
- Portals that require SSO, SAML, or a client certificate may use a flow that the accessibility automation cannot fill.
- A GlobalProtect update can change the interface and require new accessibility selectors.
- The app is not notarized by Apple. It is a local build with a local signing identity.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history.

## Uninstall

```sh
bash scripts/uninstall.sh
```

This quits the app, removes `~/Applications/OneTapVPN.app` and `/Applications/OneTapVPN.app` if present, removes the LaunchAgent, and boots out the launchd service.

To also delete the saved Keychain item:

```sh
bash scripts/uninstall.sh --purge
```

The purge option permanently removes the stored credentials.

To also remove the local signing identity:

```sh
rm -rf ~/.config/onetapvpn/signing
security delete-keychain ~/Library/Keychains/onetapvpn-signing.keychain-db
```

Only do this if you do not plan to rebuild the app.
