# Homzy mobile (Flutter Native)

The Android and iOS app uses native Flutter screens and connects directly to the same
Supabase project and FastAPI services as `homzy-ai.com`.

Native areas include authentication, Arabic/English direction, Homzy AI chat,
projects and search, favorites, listings, broker CRM and matching units,
messages, co-broking, launches, valuation, storefronts, Homzy Stays, the agency
owner-acquisition pipeline and team management.

## Run

```powershell
cd mobile
flutter pub get
flutter run
```

## Verify and build

```powershell
flutter analyze
flutter test
flutter build apk --release
flutter build appbundle --release
# On macOS with Xcode and an Apple Developer team selected:
flutter build ipa --release
```

Android release builds require the ignored `android/key.properties` and upload
keystore. The Play Store bundle is generated under
`build/app/outputs/bundle/release/`. Keep the upload keystore and its password
backed up securely because every future Android update depends on them.

The iOS project uses bundle ID `com.homzy.app`. Open `ios/Runner.xcworkspace`
on macOS, select the Apple Developer team, then archive and upload through
Xcode or build an IPA with Flutter.
