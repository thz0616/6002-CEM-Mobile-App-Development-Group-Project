# Project Setup

## Requirements

- Flutter installed
- Android SDK installed
- Android emulator or Android device available
- If using the Accounting AI features:
  - Ollama running on the host machine
  - A usable model available, for example `gemma4:31b-cloud`

## First-Time Setup

Open a terminal in this project folder and run:

```powershell
flutter pub get
```

## Running the App

For Android emulator:

```powershell
.\run.ps1 -HostIp 10.0.2.2 -LlmModel gemma4:31b-cloud
```

For a real Android device, replace `10.0.2.2` with the host computer IP that the phone can reach:

```powershell
.\run.ps1 -HostIp <host-computer-ip> -LlmModel gemma4:31b-cloud
```

You can also run Flutter directly:

```powershell
flutter run --dart-define=HOST_IP=<host-computer-ip> --dart-define=LLM_MODEL=gemma4:31b-cloud
```

## Permissions

- For SMS detection, grant the requested SMS and notification permissions on the Android device.

## Troubleshooting

- If Flutter dependencies are missing, run `flutter pub get` again.
- If the emulator cannot reach the host machine, use `10.0.2.2` as the host IP.
- If using a real device, make sure the phone and host computer are on the same network.
- If the Accounting AI feature cannot respond, confirm Ollama is running and the selected model is available.
