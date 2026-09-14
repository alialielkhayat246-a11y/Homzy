# Homzy mobile (Flutter Native)

The Android app uses native Flutter screens and connects directly to the same
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
```

The APK is generated under `build/app/outputs/flutter-apk/`. The current
Android project still uses its existing debug signing configuration for local
release builds. Store publishing requires a production application id, upload
keystore and Play signing setup.
