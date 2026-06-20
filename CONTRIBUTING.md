# Contributing

## Local Setup

Requirements:

- macOS 14 or newer.
- Xcode command line tools.
- Codex Desktop signed in if you want to test live usage requests.

Build:

```sh
xcodebuild \
  -project Traice.xcodeproj \
  -scheme "Traice" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  build
```

Test:

```sh
xcodebuild \
  -project Traice.xcodeproj \
  -scheme "Traice" \
  -destination "platform=macOS" \
  test
```

Install locally:

```sh
./install-native.sh
```

## Guidelines

- Do not log access tokens or account IDs.
- Keep private endpoint assumptions isolated in the shared usage module.
- Prefer tests around decoding, display formatting, and error behavior before changing usage models.
- Document any endpoint or auth-file shape changes in the README.
