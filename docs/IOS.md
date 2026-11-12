# Spendwell on iPhone: plan

The app is built with Flutter, so the iPhone app is the same code as Android. This plan covers what's left: Apple accounts, signing, iOS-only features and App Store review.

## Today: the web app (free, no Apple account)

iPhone users can use Spendwell right now in Safari:

1. Open https://semwal28.github.io/spendwell/
2. Tap **Share → Add to Home Screen**.

It opens full screen like an app, with the same features except receipt scan, app lock and the home screen widget. (The repository owner must first turn on GitHub Pages: **Settings → Pages → Source: GitHub Actions**.)

## Step 1. The iOS app compiles (done in CI)

Every push runs the **iOS build (no signing)** job in [CI](../.github/workflows/ci.yml) on a free macOS runner. It's marked as informational until steps 2–4 are done. If it fails, the log shows which plugin or setting needs attention.

## Step 2. Apple Developer Program (you)

- Join at https://developer.apple.com/programs/ (99 US dollars a year; needed for TestFlight and the App Store).
- In App Store Connect, create the app: name **Spendwell**, bundle ID **app.spendwell**, SKU `spendwell`.

No Mac? That's fine for everything after this step: builds and uploads can run in the cloud.

## Step 3. Signing and TestFlight in the cloud

Pick one:

| Option | Cost | What you do |
|---|---|---|
| **Codemagic** (recommended to start) | Free tier: 500 macOS build minutes a month | Connect the GitHub repo, add an App Store Connect API key, and Codemagic creates the certificate and profile for you. |
| **GitHub Actions** | Free for public repos | Add an App Store Connect API key and a distribution certificate as repository secrets; a workflow runs `flutter build ipa` and uploads to TestFlight. |

Either way, the App Store Connect API key is made in **App Store Connect → Users and Access → Integrations → App Store Connect API**. Store it only as a secret in Codemagic or GitHub, never in the code.

Then testers install the app through **TestFlight** (up to 10,000 people, no review for internal testers).

## Step 4. iOS-specific work

| Item | Status | Notes |
|---|---|---|
| Face ID for app lock | Done | `NSFaceIDUsageDescription` is in `Info.plist`. |
| Camera and photos for receipts | Done | Usage text is in `Info.plist`. |
| Receipt scan (ML Kit) | Half done | Linker flags are set. Still to add: `LatinOCRResources.bundle` to the Runner target's Copy Bundle Resources (see the `google_mlkit_text_recognition` README). Until then, receipt scan is hidden on iPhone (`lib/services/receipt/scanner_mobile.dart`). |
| Home screen widget | To do | Needs a WidgetKit extension (Swift) and an App Group `group.app.spendwell`, plus `HomeWidget.setAppGroupId` in the app. Needs Xcode once (a Mac, or a cloud Mac on Codemagic). |
| Free on-device AI | To do | Apple's Foundation Models framework (iOS 26, Apple Intelligence iPhones) runs a model on the phone: free, private and offline. A small Swift plugin can power the AI coach there without any server. |
| Privacy manifest | To do | Add `PrivacyInfo.xcprivacy` declaring UserDefaults use (shared_preferences). Plugins ship their own. |
| App Privacy answers | To do | In App Store Connect: email address and financial info (user content) are collected, linked to the user, not used for tracking. |
| Sign in with Apple | Not needed | Only required when an app offers other third-party logins; Spendwell uses email codes. |
| Account deletion | Done | Settings → Delete account (App Store rule 5.1.1(v)). |
| Bank SMS | Paste only | iOS never lets apps read SMS; pasting works the same as on Android. |
| Budget alerts when the app is closed | Later | Needs push notifications (an APNs key and a small server job). |

## Step 5. App Store release

1. Screenshots: 6.9-inch and 6.5-inch iPhone sizes (the web screenshots in `docs/screenshots/` are a starting point).
2. Store text: reuse [STORE_LISTING.md](STORE_LISTING.md).
3. Privacy policy URL: publish [PRIVACY.md](PRIVACY.md) (for example on GitHub Pages).
4. Submit for review. First reviews usually take one to three days.

## Who does what

| Step | You | Claude (in a session) |
|---|---|---|
| Turn on GitHub Pages | ✓ | |
| Apple Developer account, App Store Connect app | ✓ | |
| App Store Connect API key into Codemagic or GitHub secrets | ✓ | |
| ML Kit bundle, widget extension, privacy manifest, on-device AI plugin | | ✓ |
| TestFlight workflow | | ✓ (after the key is added) |
| Store listing, screenshots, review answers | ✓ with help | ✓ drafts |
