# Release checklist

Work down the list in order. Each step says what you need.

## 1. Backend (once)

Needs: a Supabase account and a Claude API key.

- [ ] Create a Supabase project. Pick the Mumbai region if most users are in India.
- [ ] Run `scripts/deploy_backend.sh <project-ref>`. It creates the tables, saves the Claude key and deploys both server functions.
- [ ] Authentication → Email templates → Magic link: include `{{ .Token }}`.
- [ ] Authentication → Rate limits: keep the defaults, or lower "emails per hour" while testing.
- [ ] Set up a custom email sender (Authentication → SMTP), because Supabase's built-in sender is limited and only meant for testing.

## 2. Android signing key (once)

Needs: Java (comes with Android Studio). Keep the key and passwords safe: losing them means you can't update the app.

```bash
keytool -genkey -v -keystore ~/spendwell-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `android/key.properties` (git ignores it):

```
storeFile=/home/you/spendwell-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

### Use the same key for GitHub Releases

So that each APK on GitHub Releases installs as an update, give the release workflow your key. In the repository, open **Settings → Secrets and variables → Actions → New repository secret** and add:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the output of `base64 -w0 ~/spendwell-upload.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | the store password |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | the key password |

Without them, each release is signed with a temporary test key, and people have to uninstall the old version first.

## GitHub Release (APKs for testers)

1. Raise `version:` in `pubspec.yaml` and `kAppVersion` in `lib/core/brand.dart`.
2. Write the notes in `docs/releases/vX.Y.Z.md`.
3. Push a tag:

```bash
git tag vX.Y.Z
```

```bash
git push origin vX.Y.Z
```

The [Release workflow](../.github/workflows/release.yml) runs the tests, builds both APKs and publishes the release.

## 3. Build for Google Play

```bash
flutter build appbundle --release --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

The file to upload is `build/app/outputs/bundle/release/app-release.aab`.

Before each release, raise `version:` in `pubspec.yaml` (for example `0.1.0+1` → `0.1.1+2`). The number after `+` must always go up.

## 4. Google Play

Needs: a Google Play developer account (one-time US$25).

- [ ] Create the app. The package name is `app.spendwell` and can't change later.
- [ ] Store listing: copy from `docs/STORE_LISTING.md`, add screenshots and the icon (`docs/icon.png`).
- [ ] Privacy policy: finish `docs/PRIVACY.md` and host it at a public URL (for example GitHub Pages).
- [ ] Data safety form: answers are in `docs/STORE_LISTING.md`.
- [ ] Account deletion: in the app it's Settings → Delete account. Play also asks for a web link where people can request deletion without the app; a page that gives your support email works.
- [ ] Internal testing track first, then closed testing with at least 12 testers for 14 days (Play's rule for new personal developer accounts at the time of writing; check the current rule in Play Console), then production.

## 5. iOS (later)

Needs: a Mac with Xcode and an Apple Developer account (US$99/year).

- [ ] Open `ios/Runner.xcworkspace`, set the team and bundle id (`app.spendwell`).
- [ ] `flutter build ipa --release --dart-define=...`, then upload with Xcode or Transporter.
- [ ] App Store Connect: listing, privacy "nutrition label" (same answers as Play's data safety form), screenshots.
