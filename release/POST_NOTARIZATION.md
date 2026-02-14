# Post-Notarization Steps

Submission ID: `3ed593ed-2dd7-4282-87af-f0b8aa17dd5b`

## 1. Check if notarization is complete

```bash
xcrun notarytool info 3ed593ed-2dd7-4282-87af-f0b8aa17dd5b \
  --apple-id <YOUR_APPLE_ID> \
  --team-id 746QH4Y2WY \
  --password <APP_SPECIFIC_PASSWORD>
```

Look for `status: Accepted`.

If it shows `Invalid`, fetch the log to see what went wrong:

```bash
xcrun notarytool log 3ed593ed-2dd7-4282-87af-f0b8aa17dd5b \
  --apple-id <YOUR_APPLE_ID> \
  --team-id 746QH4Y2WY \
  --password <APP_SPECIFIC_PASSWORD>
```

## 2. Staple the notarization ticket to the DMG

```bash
xcrun stapler staple release/NoteTaker-1.0.0.dmg
```

## 3. Verify the final DMG

```bash
spctl --assess --type open --context context:primary-signature release/NoteTaker-1.0.0.dmg
```

## 4. Distribute

After stapling, the DMG is fully ready. Users can double-click to install with no Gatekeeper warnings.

SHA-256 (pre-staple): `43600949081d6f1386db5e48328b81f1d2681c74cf2e67096237275508e29069`

Note: The SHA-256 will change after stapling. Generate a new one if needed:

```bash
shasum -a 256 release/NoteTaker-1.0.0.dmg
```
