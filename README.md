# OneTapVPN

OneTapVPN is a macOS menu bar app for the official Palo Alto Networks GlobalProtect client. One click connects the VPN: the app generates the TOTP code locally and fills the GlobalProtect login form for you.

It does not include, replace, or modify GlobalProtect. It automates the client you already have.

## Requirements

- macOS 13 or later
- The official GlobalProtect client installed and able to connect manually
- Xcode Command Line Tools (`xcode-select --install`)
- Admin access only if you install to `/Applications`

The project builds with Swift 6.2 in Swift 5 language mode and has no external dependencies.

## Build

Create the local signing identity once. It keeps the Accessibility permission stable across rebuilds:

```sh
bash scripts/setup-signing.sh
```

Then build:

```sh
bash scripts/build.sh
```

The app bundle is written to `build/OneTapVPN.app`. The script compiles every Swift file under `Sources`, copies `Resources/Info.plist`, and signs the bundle with the local identity. If the identity is missing, the script falls back to an ad-hoc signature and prints a warning.

To run only the compiler check:

```sh
bash scripts/typecheck.sh
```

### App icon

`onetapicon.jpeg` in the repository root is the icon source. Regenerate the macOS icon asset with:

```sh
bash scripts/make-icon.sh
```

The script trims the dark padding around the artwork, makes the corners transparent, writes `Resources/AppIcon.icns`, and `scripts/build.sh` embeds that file into the app bundle. The build generates the asset automatically when it is missing.

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

This installs to `/Applications/OneTapVPN.app`. It requires an account that can write to `/Applications`.

To build without installing, run `bash scripts/build.sh` and copy `build/OneTapVPN.app` wherever you need it.

## First run

1. Click the OneTapVPN icon in the menu bar and choose Settings.
2. Enter the portal, username, and password.
3. Enter the TOTP secret, paste a complete otpauth URI, or click Scan QR Code and point the camera at the QR code from your authenticator.
4. Verify that the live code matches the code shown by your authenticator app.
5. Save the settings.
6. Grant Accessibility access in System Settings > Privacy & Security > Accessibility.
7. Click Test Connection and approve the GlobalProtect login if prompted.

The app appears in the menu bar and in the Dock. Click the Dock icon to open Settings, or use the menu bar icon for one-click connect and disconnect.

## Camera scanning

Click Scan QR Code next to the TOTP secret field and point the camera at the QR code from your authenticator app. OneTapVPN accepts standard `otpauth://totp/...` codes and plain base32 secrets. The camera is active only while the scanner is open, and no image or video is stored or transmitted.

## How it works

- Credentials are stored in the macOS Keychain, not in a plain text file.
- The TOTP code is computed locally from the stored secret.
- The app uses the macOS Accessibility API to find the official GlobalProtect windows and fill the login form.
- GlobalProtect performs the actual VPN connection and keeps its own configuration.

OneTapVPN does not replace GlobalProtect, bundle its binaries, or change VPN profiles, routes, DNS settings, or certificates.

## Security notes

- The password and TOTP secret are stored in the Keychain and are not written to disk in plain text.
- The app makes no network connections. Only GlobalProtect contacts the VPN gateway.
- The camera is used only to decode the QR code while the scanner sheet is open. Frames are not stored or transmitted.
- Storing the password and TOTP secret together makes two-factor authentication effectively single-factor. Anyone who can read the stored credentials can produce both factors.
- Accessibility permission lets OneTapVPN inspect and control other apps. Grant it only to a build you trust.
- Check your employer's IT policy before use. Automating a corporate VPN client may be restricted or forbidden.
- The app is signed with a local self-signed code signing identity, not by Apple. The private key stays in `~/.config/onetapvpn/signing` and `~/Library/Keychains/onetapvpn-signing.keychain-db`. The stable identity keeps the Accessibility permission across rebuilds. Build and install it on the Mac where you use it.

## Troubleshooting

### Accessibility permission is not granted

Open System Settings > Privacy & Security > Accessibility and enable OneTapVPN. If there are several OneTapVPN entries, remove all of them with the minus button, add `~/Applications/OneTapVPN.app` again, and restart OneTapVPN. Use the installed app, not a copy from the build folder. The local signing identity keeps this permission stable across future rebuilds.

### Camera permission is not granted

Open System Settings > Privacy & Security > Camera and enable OneTapVPN. If the app is not listed, open the QR scanner once to trigger the permission request. Without camera access, paste the TOTP secret or otpauth URI instead.

### Login fields are not found

Open GlobalProtect manually and confirm that its sign-in window appears. Portals that require SSO, SAML, or a client certificate may use a flow that OneTapVPN cannot fill. Generate a diagnostic report to see which accessibility elements were found.

### Diagnostic report

The app writes accessibility diagnostics to `~/Library/Logs/OneTapVPN`. Review the report before sharing it because it can contain portal or account text.

### Password changed

Open Settings, enter the new password, and save. The next connection uses the updated password.

### TOTP code mismatch

Confirm that the secret, digits, period, and algorithm match the authenticator entry. Enable automatic date and time on the Mac so the TOTP clock stays in sync.

### GlobalProtect updated and the UI changed

A GlobalProtect update can change accessibility labels and break automation. Reopen OneTapVPN and generate a diagnostic report. Supporting a new interface requires updating the accessibility selectors in the source.

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
