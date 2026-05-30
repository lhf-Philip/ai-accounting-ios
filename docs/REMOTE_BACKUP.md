# WebDAV Remote Backup

AI Accounting supports manual WebDAV remote backup on iOS and Android. Remote backup is not live sync: upload and restore are deliberate user actions.

## Encryption Modes

Remote backup has two modes.

| Mode | Default | File type | Passphrase required for upload | Passphrase required for restore | Notes |
| --- | --- | --- | --- | --- | --- |
| Encrypted remote backup | Yes | `.aibackup` | Yes | Yes | Recommended. The backup JSON is wrapped in an AES-GCM envelope before upload. |
| Plain JSON remote backup | No | `.json` | No | No | Opt-in only. The cloud provider can read the financial backup content. |

The app defaults to `Encrypt remote backups (recommended)` on both platforms. Users can turn it off manually from the WebDAV remote backup settings screen.

## What The Passphrase Does

The WebDAV username and password are only used to connect to the WebDAV server.

The backup passphrase is separate. It is only used to encrypt or decrypt `.aibackup` files. It is not needed for:

- Testing the WebDAV connection
- Listing remote backups
- Uploading a plain `.json` backup
- Restoring a plain `.json` backup

It is needed for:

- Uploading an encrypted `.aibackup` backup
- Restoring an encrypted `.aibackup` backup

If the passphrase is lost, encrypted `.aibackup` files cannot be recovered by the app.

## Plain JSON Risk

Plain `.json` remote backups contain personal finance data such as accounts, transactions, notes, categories, tags, budgets, debts, and advances. They should only be used when the WebDAV storage is already trusted and protected by the user.

The app warns before unencrypted uploads. HTTP WebDAV remains supported for local or LAN testing, but HTTPS is strongly preferred. Using HTTP with plain JSON is the highest-risk combination because the data is exposed both in transit and at rest.

## Restore Behaviour

The restore flow detects the selected remote file format.

- `.aibackup`: asks for a passphrase and decrypts before preview/restore.
- `.json`: previews and restores directly without a passphrase.
- Unknown file format: rejected.

Restore still overwrites local app data after confirmation. Export a local backup first when testing real data.

## Platform Parity

The expected behaviour is the same on iOS and Android:

- Encryption is enabled by default.
- Encrypted upload requires a non-empty passphrase.
- Plain JSON upload does not require a passphrase.
- Encrypted restore requires a passphrase.
- Plain JSON restore does not require a passphrase.
- Remote backup lists show whether a file is encrypted or unencrypted.
- HTTP risk warnings are stronger when encryption is disabled.

## Manual Validation Checklist

Use this checklist when changing WebDAV backup code or UI.

1. Connection test works with WebDAV URL, username, and password only.
2. Encrypted upload without passphrase is blocked.
3. Encrypted upload with passphrase creates `.aibackup`.
4. Encrypted restore without passphrase is blocked.
5. Encrypted restore with the correct passphrase previews and restores.
6. Plain upload without passphrase creates `.json`.
7. Plain restore previews and restores without passphrase.
8. Wrong passphrase for `.aibackup` shows a clear failure and does not restore.
9. HTTP WebDAV shows a risk warning; HTTP plus plain JSON shows the stronger warning.
10. Remote backup list labels `.aibackup` as encrypted and `.json` as unencrypted.
