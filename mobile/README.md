# Homzy mobile (Flutter) — Phase 3

The cross-platform (Android + iOS) app that wraps the Homzy brain. It reuses the
same brand system as the web chat (navy `#0D1B2A`, blue `#2563EB`, Poppins +
Cairo, house-with-window logo) and talks to the existing FastAPI backend over
`/api/chat`, `/api/health`, `/api/reset`.

> **Status:** app source is scaffolded (splash, onboarding-style home dashboard,
> bilingual chat, bottom nav). The native `android/` and `ios/` folders are **not**
> committed — regenerate them with `flutter create .` (see below). Not yet
> compiled/run end-to-end; that needs the Flutter SDK installed.

## What's here
```
mobile/
├─ pubspec.yaml            deps: http, google_fonts, shared_preferences
├─ analysis_options.yaml
└─ lib/
   ├─ main.dart            app entry + MaterialApp
   ├─ theme.dart           Brand tokens + ThemeData (Poppins/Cairo)
   ├─ api.dart             HomzyApi client + models (configurable base URL)
   ├─ widgets/
   │  └─ house_logo.dart   the house mark + circular broker avatar (CustomPaint)
   └─ screens/
      ├─ splash_screen.dart
      ├─ root_nav.dart     bottom nav: Home / Projects / Chat / Saved / Profile
      ├─ home_screen.dart  dashboard: status pill, "continue your journey", feature cards
      ├─ chat_screen.dart  bilingual + RTL chat, chips, typing, bot avatar
      └─ placeholder_screen.dart   stubs for Projects/Saved/Profile
```

## Run it

1. **Install Flutter** (3.22+): https://docs.flutter.dev/get-started/install
   Then `flutter doctor` until Android (and/or iOS) toolchain is green.

2. **Generate the native platform folders** (one-time, in this folder):
   ```bash
   cd mobile
   flutter create .
   flutter pub get
   ```
   `flutter create .` adds `android/`, `ios/`, etc. without touching `lib/`.

3. **Start the backend** (from the repo root) so the app has an API to call:
   ```bash
   python -m uvicorn backend.app:app --host 0.0.0.0 --port 8000
   ```
   Use `0.0.0.0` (not `127.0.0.1`) if you want a physical phone on your Wi-Fi to
   reach it.

4. **Run the app:**
   ```bash
   flutter run
   ```

## Pointing the app at your backend

The API base URL is configurable and saved on the device:

- **Android emulator** → host PC is `http://10.0.2.2:8000` (the default).
- **iOS simulator** → `http://127.0.0.1:8000`.
- **Physical phone** → your PC's LAN IP, e.g. `http://192.168.1.20:8000`.

Set it at build time:
```bash
flutter run --dart-define=HOMZY_API=http://192.168.1.20:8000
```
…or at runtime from the **⚙/tune icon in the chat screen's app bar**.

## Notes
- `google_fonts` fetches Poppins/Cairo on first launch (then caches). To ship
  fully offline, bundle the font files and switch `theme.dart` to `TextTheme`.
- Grounding guarantee is unchanged: the app only displays what the backend
  returns — prices come from `data/listings.json`, never invented.
- Next: app icon (navy house mark), Projects/Saved/Profile screens, and hosting
  the backend so the app works off your local PC (see docs/PROJECT_PLAN.md §9).
