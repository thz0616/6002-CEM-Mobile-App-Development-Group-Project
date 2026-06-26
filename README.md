# EarEye — Android AI Personal Assistant (Flutter)

> An all-in-one Android personal-assistant app built with Flutter, bundling an LLM chat, on-device ML, OCR-based scanners, an accounting helper, expiry/macro planners, and a scan-to-calendar workflow into a single home-screen grid.

This project is the repository for the EarEye Android app.

---

## ✨ Features

| Feature | Module | Description |
| --- | --- | --- |
| 🤖 **AI Chat** | [chat_screen.dart](lib/ui/screens/chat_screen.dart), [llm_service.dart](lib/data/services/llm_service.dart) | Conversational chat backed by Google Gemini or a local Ollama model. |
| 🧠 **Chat Mode** | [chat_mode_screen.dart](lib/ui/screens/chat_mode_screen.dart) | Dedicated assistant-mode chat UI. |
| 🧾 **Accounting AI** | [accounting_screen.dart](lib/ui/screens/accounting_screen.dart) | Ingests account screenshots, extracts transactions, stores them locally. |
| 🥗 **Allergen Scanner** | [allergen_scanner_screen.dart](lib/ui/screens/allergen_scanner_screen.dart), OCR + result screens | Camera/OCR scan of food/product labels matched against a user allergen profile. |
| 💊 **Medication Cabinet** | [medication_cabinet_screen.dart](lib/ui/screens/medication_cabinet_screen.dart) | Local SQLite-backed medication list. |
| ⚠️ **Medication Validation** | [medication_validation_screen.dart](lib/ui/screens/medication_validation_screen.dart) | Drug-interaction checks powered by the on-device ML model. |
| ⏰ **Expiry Tracker** | [expiry_tracker_screen.dart](lib/ui/screens/expiry_tracker_screen.dart) | Track product expiry dates with TTS reminders. |
| 🍱 **Macro Planner** | [macro_planner_screen.dart](lib/ui/screens/macro_planner_screen.dart) | Meal/macro planning backed by the public MealDB API. |
| 🗓️ **Plan Check-in / Saved Plans** | [plan_checkin_screen.dart](lib/ui/screens/plan_checkin_screen.dart), [saved_plans_screen.dart](lib/ui/screens/saved_plans_screen.dart) | Recurring plan/goal tracking with check-ins. |
| 📅 **Scan-to-Calendar** | [scan_to_calendar_screen.dart](lib/ui/screens/scan_to_calendar_screen.dart) | Scan a document and auto-add events via `add_2_calendar`. |
| 🛡️ **SMS Scam Detection** | [sms_scam_detection_screen.dart](lib/ui/screens/sms_scam_detection_screen.dart) | On-device DistilBERT classifier (`.tflite`) for SMS scam detection. |
| ✉️ **Auto-send / Summarizer** | [auto_send_screen.dart](lib/ui/screens/auto_send_screen.dart), [summarizer_screen.dart](lib/ui/screens/summarizer_screen.dart) | Summarize content and auto-draft outgoing messages. |
| ⚙️ **Settings** | [settings_screen.dart](lib/ui/screens/settings_screen.dart) | App configuration & model selection. |

---

## 🏗️ Architecture

A clean layered Dart architecture under [lib/](lib/):

```
lib/
├── main.dart                 # App entry — boots SharedPreferences + Riverpod
├── core/                     # Cross-cutting utilities (network, helpers)
│   └── utils/
├── domain/                   # Plain Dart business types
│   ├── models/               #   account_transaction, medication, product_data, selected_allergens
│   └── repositories/         #   Repository contracts
├── data/                     # Concrete implementations
│   ├── services/             #   llm_service, sms_scam_detection, OCR, ML, DB, etc.
│   └── repositories/         #   conversation, settings, plans
└── ui/                       # Presentation
    ├── providers/            #   Riverpod state notifiers
    └── screens/              #   Material 3 screens
```

**Key design notes**

- **State management** — [flutter_riverpod](https://pub.dev/packages/flutter_riverpod); `ProviderScope` overrides inject `SharedPreferences` at startup in [main.dart](lib/main.dart).
- **AI layer** — [llm_service.dart](lib/data/services/llm_service.dart) calls Google Gemini with model fallback. A local **Ollama** model (e.g. `gemma4:31b-cloud`) can also be used by pointing the app at the host machine's IP.
- **On-device ML** — `tflite_flutter` runs a DistilBERT classifier in [assets/ml/](assets/ml/) for SMS scam detection; a custom `MethodChannel('com.example.app/sms_scam_control')` bridges to the Android notification/SMS listener.
- **Persistence** — `sqflite` for medications/transactions; `shared_preferences` for settings/plans.
- **Native capabilities** — camera (`image_picker`), mic (`record` + `speech_to_text`), text recognition (`google_mlkit_text_recognition`), QR/barcode (`mobile_scanner`), contacts, TTS, calendar insertion, `url_launcher`, `permission_handler`, `network_info_plus`.

Design history & per-feature design docs live in [docs/plans/](docs/plans/).

---

## 🚀 Setup & Run

### Requirements

- Flutter SDK installed
- Android SDK installed
- Android emulator or a physical Android device
- For the **Accounting AI** / chat features backed by a local LLM:
  - Ollama running on the host machine
  - A usable model, e.g. `gemma4:31b-cloud`

### First-time setup

```powershell
flutter pub get
```

### Run the app

**Android emulator** (host reachable at `10.0.2.2`):

```powershell
.\run.ps1 -HostIp 10.0.2.2 -LlmModel gemma4:31b-cloud
```

**Physical Android device** (replace with the host machine's LAN IP):

```powershell
.\run.ps1 -HostIp <host-computer-ip> -LlmModel gemma4:31b-cloud
```

Or call Flutter directly:

```powershell
flutter run --dart-define=HOST_IP=<host-computer-ip> --dart-define=LLM_MODEL=gemma4:31b-cloud
```

### Permissions

- **SMS detection** — grant the requested SMS + notification permissions on the device.
- **Allergen / document scanning** — camera permission is requested on first use.
- **Voice features (speech-to-text, TTS)** — mic permission is requested on first use.

### Troubleshooting

- Missing Flutter deps? Re-run `flutter pub get`.
- Emulator can't reach the host? Use `10.0.2.2` as `HOST_IP`.
- Real device can't reach the host? Make sure phone + host are on the **same network** and that the host firewall allows the port Ollama is listening on (default `11434`).
- Accounting AI / local LLM not responding? Confirm Ollama is running (`ollama serve`) and that the selected model is pulled (`ollama pull gemma4:31b-cloud`).

---

## 🛠️ Build & Dev Commands

| Command | What it does |
| --- | --- |
| `flutter pub get` | Install Dart/Flutter dependencies. |
| `flutter run --dart-define=HOST_IP=... --dart-define=LLM_MODEL=...` | Run the app with runtime config. |
| `flutter build apk --release` | Produce a release APK. |
| `dart run build_runner build --delete-conflicting-outputs` | Regenerate `.g.dart` files (e.g. for `product_data`). |
| `flutter analyze` | Static analysis. |
| `flutter test` | Run unit / widget tests. |

### Smoke-testing the SMS model

A standalone harness exists in [test_fda.dart](test_fda.dart) to exercise the on-device model during development.

---

## 📁 Notable Files

- [lib/main.dart](lib/main.dart) — entry point
- [lib/ui/screens/home_screen.dart](lib/ui/screens/home_screen.dart) — home grid + SMS scam deep-link entry
- [lib/data/services/llm_service.dart](lib/data/services/llm_service.dart) — Gemini / Ollama client
- [lib/data/services/sms_scam_detection_service.dart](lib/data/services/sms_scam_detection_service.dart) — native bridge
- [assets/ml/spam_sms_distilbert.tflite](assets/ml/spam_sms_distilbert.tflite) — on-device SMS classifier
- [FRIEND_SETUP.md](FRIEND_SETUP.md) — short setup notes (kept for quick reference)

---

## 📄 License

Internal FYP project — not currently published to pub.dev (see `publish_to: 'none'` in [pubspec.yaml](pubspec.yaml)).
