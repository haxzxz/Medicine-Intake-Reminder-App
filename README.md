<p  align="center">
    <img src="./web/icon.png" width=167>
<p>

<h1 align="center"><a href="https://haxzxz.github.io/Medicine-Intake-Reminder-App/">ZAM: Zealous Assistant for Medication</a></h1>

A voice-powered medicine reminder application designed to help users of all ages manage their medication schedules with ease. By combining smart reminders, voice commands, and medicine information, the app ensures that users never miss a dose. It also maintains logs and a history for better tracking, making it especially useful.  

<hr>

## Table of Contents
- [How It Works](#how-it-works)
- [Meet The Team](#meet-the-team)
- [Tech Stacks](#tech-stacks)
- [Project Structure](#project-structure)
- [Features](#features)
- [App Development Requisites | Setting Up](#app-development-requisites--setting-up)
  - [Firebase Setup](#1-firebase-setup)
  - [Backend Environment](#2-backend-environment)
  - [Run The Backend Locally](#3-run-the-backend-locally)
  - [Flutter Environment](#4-flutter-environment)
  - [Run The Flutter App](#5-run-the-flutter-app)
  - [Backend API Routes](#6-backend-api-routes)
  - [Deploy Backend To Render](#7-deploy-backend-to-render)
  - [Build Android APK](#8-build-android-apk)
  - [Running on a Physical Android Device (USB)](#running-on-a-physical-android-device-usb)
  - [Static Download Website](#9-static-download-website)
- [Troubleshooting](#troubleshooting)
- [Past Git History with Vulnerabilities(API key exposed, etc.)](#git-history-including-past-commits-with-vulnerabilities)

## How It Works
1. <b>Set a Medicine Reminder</b> - The user speaks or types the medicine name and time. The assistant confirms the request and schedules the reminder automatically. Active reminders are displayed on the dashboard. 
2. <b>Receive Smart Notifications</b> - When it is time to take the medicine, the assistant sends a timely alert. The user can mark the dose as Taken, choose to Snooze the reminder, or mark it as Missed.  
3. <b>View Medicine Information</b> - The assistant provides basic details about medicines, including their purpose and usage, whenever the user asks. This helps the user understand what they are taking. 
4. <b>Track Logs and History</b> -  All completed or missed doses are recorded in the Logs section. The user can review their intake history at any time to monitor consistency.

<hr>

## Features

- <b>Bi-Lingual Support</b>: Support Both English and Filipino Language.
- <b>Voice Reminders</b>: Set and manage medication schedules hands-free using voice commands. 
- <b>AI Chat</b>: Chat naturally to log medications, automate recurring alarms, and get intake summaries.
- <b>Smart Notifications</b>: Timely, reliable alerts so you never miss a dose. 
- <b>Medicine Information</b>: Quick in-app lookups for drug uses, dosages, and safety precautions. 
- <b>Logs & History</b>: Track upcoming alarms, taken doses, and missed schedules in one list. 
- <b>Data Privacy</b>: Secure handling and encryption of your personal medication data. 

<hr>

## Meet The Team

| Member | Role |
| :------: | :----: |
| Manalo, Zamantha Artlyn O. | Project Manager, Quality Assurance |
| Librada, Ma. Cathleen O. | UI/UX, Quality Assurance |
| Ebero, Christian James O. | Fullstack Developer |

<hr>

## Tech Stacks
```text
Mobile app:
  Flutter          Cross-platform app framework
  Dart             Main programming language for the Flutter app

Backend:
  Flask            Python web API framework
  Python           Backend programming language
  Gunicorn         Production server for running the Flask API on Render

AI:
  Google Gemini    AI service used by the app/backend for smart reminder features

Deployment:
  Render           Hosts/deploys the Flask backend
  render.yaml      Render deployment blueprint
  Procfile         Backend start command for hosting

Static website:
  HTML             Download page structure
  CSS              Download page styling
  JavaScript       Download page interactivity

Platform support:
  Android          Main mobile build target
  iOS              iPhone/iPad build target
  Web              Flutter web support plus static APK download site
  Windows          Flutter desktop support
  macOS            Flutter desktop support
  Linux            Flutter desktop support

Build/config tools:
  Gradle           Android build system
  CMake            Windows/Linux desktop build configuration
  Xcode files      iOS/macOS project configuration
  pubspec.yaml     Flutter/Dart dependency configuration
  requirements.txt Python dependency configuration
```

<hr>

## Project Structure

```text
reminder-app/
  .github/          GitHub configuration/workflows folder
  .venv-con/        Local Python virtual environment folder
  back_end/         Flask API for Gemini, users, reminders, and logs
    app.py          Main Flask application and API routes
    config.py       Backend configuration settings
    requirements.txt Python dependencies for the Flask API
    Procfile        Process command for deployment hosting
  front_end/        Flutter mobile app
    lib/            Main Flutter source code
      main.dart     Flutter app entry point
      models/       Reminder and reminder log data models
      screens/      App screens like home, login, profile, and logs
      services/     Auth, backend, Gemini, notification, storage, and parser services
      widgets/      Reusable UI pieces like reminder cards, chat bubbles, and logo
    assets/         App images and bundled assets
    android/        Android Flutter project files and native config
    ios/            iOS Flutter project files and native config
    web/            Flutter web build/support files
    windows/        Windows desktop Flutter support files
    macos/          macOS desktop Flutter support files
    linux/          Linux desktop Flutter support files
    test/           Flutter test files
    pubspec.yaml    Flutter dependencies and asset configuration
    pubspec.lock    Locked Flutter/Dart dependency versions
    analysis_options.yaml Dart/Flutter linting rules
    devtools_options.yaml Flutter DevTools configuration
  web/              Static APK download website
    index.html      Download page HTML
    style.css       Website styling
    script.js       Website behavior
    icon.png        Website/app icon image
    README.md       Notes for the static web page
  .gitignore        Files and folders Git should ignore
  README.md         Main project documentation
  render.yaml       Render deployment blueprint for the Flask API
```

<details>
  <summary>View the Full Explanation of Project Structure &#91;Warning It's VERY LOOONGGG&#93; </summary>

```text
  reminder-app/
  .github/          GitHub configuration/workflows folder
  .venv-con/        Local Python virtual environment folder
  back_end/         Flask API for Gemini, users, reminders, and logs
    app.py          Main Flask application and API routes
    config.py       Backend configuration settings
    Procfile        Process command for deployment hosting
    requirements.txt Python dependencies for the Flask API
  front_end/        Flutter mobile app
    analysis_options.yaml Dart/Flutter linting rules
    devtools_options.yaml Flutter DevTools configuration
    pubspec.lock    Locked Flutter/Dart dependency versions
    pubspec.yaml    Flutter dependencies, app metadata, and assets
    assets/
      images/
        zam-logo.png App logo image
    lib/
      main.dart     Flutter app entry point
      models/
        reminder.dart Reminder data model
        reminder_log.dart Reminder log/history data model
      screens/
        home_screen.dart Main reminders/chat screen
        login_screen.dart Login/authentication screen
        profile_screen.dart User profile screen
        reminder_log_screen.dart Reminder log/history screen
      services/
        auth_service.dart Authentication logic
        backend_service.dart Flask backend API client
        gemini_service.dart Gemini AI service client
        notification_service.dart Local notification scheduling
        reminder_text_parser.dart Reminder text parsing logic
        storage_service.dart Local storage/persistence logic
      widgets/
        api_key_dialog.dart API key input dialog
        chat_bubble.dart Chat message bubble UI
        reminder_card.dart Reminder card UI
        zam_logo.dart App logo widget
    test/
      widget_test.dart Flutter widget test
    android/
      build.gradle Android build configuration
      build.gradle.kts Android Kotlin build configuration
      gradle.properties Gradle settings
      settings.gradle Android project settings
      settings.gradle.kts Android Kotlin project settings
      app/
        build.gradle Android app build configuration
        build.gradle.kts Android app Kotlin build configuration
        google-services.json Firebase/Google services config
        src/
          debug/
            AndroidManifest.xml Debug Android manifest
          main/
            AndroidManifest.xml Main Android manifest
            kotlin/
              com/
                example/
                  zam_medicine_reminder/
                    MainActivity.kt Android native entry point
            res/
              drawable/
                launch_background.xml Android launch background
              drawable-v21/
                launch_background.xml Android launch background for newer devices
              mipmap-hdpi/
                ic_launcher.png Default app launcher icon
                launcher_icon.png Custom app launcher icon
              mipmap-mdpi/
                ic_launcher.png Default app launcher icon
                launcher_icon.png Custom app launcher icon
              mipmap-xhdpi/
                ic_launcher.png Default app launcher icon
                launcher_icon.png Custom app launcher icon
              mipmap-xxhdpi/
                ic_launcher.png Default app launcher icon
                launcher_icon.png Custom app launcher icon
              mipmap-xxxhdpi/
                ic_launcher.png Default app launcher icon
                launcher_icon.png Custom app launcher icon
              values/
                styles.xml Android style definitions
              values-night/
                styles.xml Android dark-mode style definitions
          profile/
            AndroidManifest.xml Profile Android manifest
      gradle/
        wrapper/
          gradle-wrapper.properties Gradle wrapper configuration
    ios/
      Flutter/
        AppFrameworkInfo.plist Flutter iOS framework metadata
        Debug.xcconfig iOS debug build settings
        Release.xcconfig iOS release build settings
      Runner/
        AppDelegate.swift iOS app delegate
        Info.plist iOS app metadata/settings
        Runner-Bridging-Header.h Swift/Objective-C bridge header
        SceneDelegate.swift iOS scene delegate
        Assets.xcassets/
          AppIcon.appiconset/
            Contents.json App icon asset metadata
            Icon-App-20x20@1x.png iOS app icon
            Icon-App-20x20@2x.png iOS app icon
            Icon-App-20x20@3x.png iOS app icon
            Icon-App-29x29@1x.png iOS app icon
            Icon-App-29x29@2x.png iOS app icon
            Icon-App-29x29@3x.png iOS app icon
            Icon-App-40x40@1x.png iOS app icon
            Icon-App-40x40@2x.png iOS app icon
            Icon-App-40x40@3x.png iOS app icon
            Icon-App-50x50@1x.png iOS app icon
            Icon-App-50x50@2x.png iOS app icon
            Icon-App-57x57@1x.png iOS app icon
            Icon-App-57x57@2x.png iOS app icon
            Icon-App-60x60@2x.png iOS app icon
            Icon-App-60x60@3x.png iOS app icon
            Icon-App-72x72@1x.png iOS app icon
            Icon-App-72x72@2x.png iOS app icon
            Icon-App-76x76@1x.png iOS app icon
            Icon-App-76x76@2x.png iOS app icon
            Icon-App-83.5x83.5@2x.png iOS app icon
            Icon-App-1024x1024@1x.png App Store icon
          LaunchImage.imageset/
            Contents.json Launch image metadata
            LaunchImage.png iOS launch image
            LaunchImage@2x.png iOS launch image
            LaunchImage@3x.png iOS launch image
            README.md Launch image notes
        Base.lproj/
          LaunchScreen.storyboard iOS launch screen layout
          Main.storyboard iOS main storyboard
      Runner.xcodeproj/
        project.pbxproj Xcode project definition
        project.xcworkspace/
          contents.xcworkspacedata Xcode workspace data
          xcshareddata/
            IDEWorkspaceChecks.plist Xcode workspace check settings
            WorkspaceSettings.xcsettings Xcode workspace settings
        xcshareddata/
          xcschemes/
            Runner.xcscheme Xcode build/run scheme
      Runner.xcworkspace/
        contents.xcworkspacedata Xcode workspace data
        xcshareddata/
          IDEWorkspaceChecks.plist Xcode workspace check settings
          WorkspaceSettings.xcsettings Xcode workspace settings
      RunnerTests/
        RunnerTests.swift iOS test file
    macos/
      Flutter/
        Flutter-Debug.xcconfig macOS debug Flutter build settings
        Flutter-Release.xcconfig macOS release Flutter build settings
        GeneratedPluginRegistrant.swift macOS generated plugin registration
      Runner/
        AppDelegate.swift macOS app delegate
        DebugProfile.entitlements macOS debug/profile permissions
        Info.plist macOS app metadata/settings
        MainFlutterWindow.swift macOS main Flutter window
        Release.entitlements macOS release permissions
        Assets.xcassets/
          AppIcon.appiconset/
            app_icon_16.png macOS app icon
            app_icon_32.png macOS app icon
            app_icon_64.png macOS app icon
            app_icon_128.png macOS app icon
            app_icon_256.png macOS app icon
            app_icon_512.png macOS app icon
            app_icon_1024.png macOS app icon
            Contents.json macOS app icon metadata
        Base.lproj/
          MainMenu.xib macOS main menu layout
        Configs/
          AppInfo.xcconfig macOS app info settings
          Debug.xcconfig macOS debug build settings
          Release.xcconfig macOS release build settings
          Warnings.xcconfig macOS warning settings
      Runner.xcodeproj/
        project.pbxproj Xcode project definition
        project.xcworkspace/
          xcshareddata/
            IDEWorkspaceChecks.plist Xcode workspace check settings
        xcshareddata/
          xcschemes/
            Runner.xcscheme Xcode build/run scheme
      Runner.xcworkspace/
        contents.xcworkspacedata Xcode workspace data
        xcshareddata/
          IDEWorkspaceChecks.plist Xcode workspace check settings
      RunnerTests/
        RunnerTests.swift macOS test file
    linux/
      CMakeLists.txt Linux build configuration
      flutter/
        CMakeLists.txt Linux Flutter build configuration
        generated_plugin_registrant.cc Generated plugin registration source
        generated_plugin_registrant.h Generated plugin registration header
        generated_plugins.cmake Generated plugin CMake config
      runner/
        CMakeLists.txt Linux runner build configuration
        main.cc Linux app entry point
        my_application.cc Linux app implementation
        my_application.h Linux app header
    windows/
      CMakeLists.txt Windows build configuration
      flutter/
        CMakeLists.txt Windows Flutter build configuration
        generated_plugin_registrant.cc Generated plugin registration source
        generated_plugin_registrant.h Generated plugin registration header
        generated_plugins.cmake Generated plugin CMake config
      runner/
        CMakeLists.txt Windows runner build configuration
        flutter_window.cpp Windows Flutter window implementation
        flutter_window.h Windows Flutter window header
        main.cpp Windows app entry point
        resource.h Windows resource header
        Runner.rc Windows app resource file
        runner.exe.manifest Windows executable manifest
        utils.cpp Windows utility functions
        utils.h Windows utility headers
        win32_window.cpp Win32 window implementation
        win32_window.h Win32 window header
        resources/
          app_icon.ico Windows app icon
    web/
      favicon.png Flutter web favicon
      index.html Flutter web shell page
      manifest.json Flutter web app manifest
      icons/
        Icon-192.png Web app icon
        Icon-512.png Web app icon
        Icon-maskable-192.png Maskable web app icon
        Icon-maskable-512.png Maskable web app icon
  web/  Static APK download website
    icon.png    Website/app icon image
    index.html  Download page HTML
    README.md   Notes for the static web page
    script.js   Website behavior
    style.css   Website styling
  .gitignore    Files and folders Git should ignore
  README.md     Main project documentation
  render.yaml   Render deployment blueprint for the Flask API
```

</details>

<hr>

## App Development Requisites | Setting Up

- <a href="https://docs.flutter.dev/install" target="_blank">Flutter SDK 3.2 or newer</a>
- <a href="https://www.python.org/downloads/" target="_blank">Python 3.11 or newer</a>
- PostgreSQL database
- Firebase project
- Render or Railway for Deployment of the Backend
- Gemini API key from <a href="https://aistudio.google.com/welcome" target="_blank">Google AI Studio</a>
- <a href="https://developer.android.com/studio" target="_blank">Android Studio </a>especially Android SDK

Confirm if Flutter is ready and running:

```powershell
flutter doctor
```

If Android licenses are not accepted yet:

```powershell
flutter doctor --android-licenses
```

### 1. Firebase Setup

Create a Firebase project for authentication.

1. Open the <a href="https://console.firebase.google.com" target="_blank">Firebase Console</a>.
2. Create a new project.
3. Add an Android app.
4. Use this Android package name:

```text
com.example.zam_medicine_reminder
```

5. Download `google-services.json`.
6. Put it here:

```text
front_end/android/app/google-services.json
```

7. In Firebase Authentication, enable the sign-in methods you want to use:
   - Email/password
   - Google

For Google sign-in, add your Android debug SHA-1 fingerprint in Firebase:

```powershell
keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

Copy the SHA-1 value into Firebase Project Settings > Your Android App > Add fingerprint.

### 2. Backend Environment

Create a backend environment file:

```text
back_end/.env
```

Use this template:

```text
GEMINI_API_KEY=your_gemini_api_key_here
BACKEND_URL=your_backend_url_here
DATABASE_URL=your_database_url_here
FIREBASE_AUTH_REQUIRED=false
CORS_ORIGINS=your_cors_origin_url_here
```

<i>Note: you can see the .env.example as template</i>.

Notes:

- `DATABASE_URL` must point to your PostgreSQL database.
- `GEMINI_API_KEY` should stay only on the backend.
- `FIREBASE_AUTH_REQUIRED=false` is convenient for local testing.
- For production, use `FIREBASE_AUTH_REQUIRED=true`.
- `CORS_ORIGINS` is required by the Flask app. Use trusted origins in production.

Create the local PostgreSQL database if you are using the default URL:

```sql
CREATE DATABASE zam_reminder;
```

### 3. Run The Backend Locally

From the project root:

```powershell
cd back_end
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe app.py
```

The API runs at:

```text
http://localhost:5000
```

Check the health endpoint:

```text
http://localhost:5000/api/health
```

Expected result:

```json
{
  "ok": true,
  "database": "ok",
  "geminiConfigured": true,
  "model": "gemini-flash-lite-latest"
}
```

### 4. Flutter Environment

Create the Flutter app environment file:

```text
front_end/.env
```

<i>Note: you can see the .env.example as template</i>.

Use one of these values:

```text
BACKEND_URL=http://10.0.2.2:5000
```

Use `10.0.2.2` for the Android emulator.

For a physical phone on the same Wi-Fi network:

```text
BACKEND_URL=http://YOUR_COMPUTER_LAN_IP:5000
```

For a deployed backend:

```text
BACKEND_URL=https://YOUR_RENDER_SERVICE.onrender.com
```

Important: Flutter bundles `.env` into the app. Rebuild the APK after changing `front_end/.env`.

### 5. Run The Flutter App

Open a new terminal from the project root:

```powershell
cd front_end
flutter pub get
flutter run
```

If you are building for Android, keep the backend running while testing chat, sync, reminders, and logs.

### 6. Backend API Routes

The Flask API currently exposes:

```text
GET     /
GET     /api/health
POST    /api/chat
GET     /api/reminders
POST    /api/reminders
PUT     /api/reminders/<client_id>
DELETE  /api/reminders/<client_id>
DELETE  /api/reminders
GET     /api/reminder-logs
POST    /api/reminder-logs
DELETE  /api/reminder-logs
```

Authenticated app requests send a Firebase bearer token. During local development, `FIREBASE_AUTH_REQUIRED=false` lets the API fall back to a development user if Firebase Admin verification is not configured.

### 7. Deploy Backend To Render

This repo includes `render.yaml`, so Render can deploy the Flask API as a Blueprint.

Render settings:

```text
Root directory: back_end
Build command: pip install -r requirements.txt
Start command: gunicorn app:app --bind 0.0.0.0:$PORT
Health check path: /api/health
```

Render environment variables:

```text
DATABASE_URL=your_postgres_connection_string
GEMINI_API_KEY=your_gemini_api_key
GEMINI_MODEL=gemini-flash-lite-latest
FIREBASE_AUTH_REQUIRED=true
CORS_ORIGINS=https://your-trusted-origin.com
```

After Render deploys, update:

```text
front_end/.env
```

Set:

```text
BACKEND_URL=https://YOUR_RENDER_SERVICE.onrender.com
```

Then rebuild the Flutter APK.

### 8. Build Android APK

From `front_end/`:

```powershell
flutter clean
flutter pub get
flutter build apk --release
```

The release APK is created at:

```text
front_end/build/app/outputs/flutter-apk/app-release.apk
```

### Running on a Physical Android Device (USB)

Follow these steps to deploy and run the Flutter frontend directly on your connected Android device:

#### Enable Developer Options
1. Connect your Android device to your computer via USB.
2. Open the **Settings** app on your device.
3. Navigate to **About Phone** and tap **Build Number** 7 times to activate **Developer Options**.
4. Go back to the main Settings menu, open **Developer Options**, and enable:
   * **USB Debugging**
   * **Stay Awake** (Optional, keeps the screen on while charging)

#### Run the Application
Open your terminal, navigate to the frontend directory, and execute the following commands:

```powershell
# Navigate to the frontend directory
cd front_end/

# Verify your device is connected and copy your DEVICE_ID
flutter devices

# Clear cache and fetch dependencies
flutter clean
flutter pub get

# Run the app on your specific device
flutter run -d <YOUR_DEVICE_SERIAL_NUMBER>
```

### 9. Static Download Website

The `web/` folder is for a simple website that lets users download the APK.

Expected APK path:

```text
web/downloads/zam-latest.apk
```

Create the folder if needed:

```powershell
New-Item -ItemType Directory -Force web\downloads
```

Copy your release APK there and rename it:

```text
zam-latest.apk
```

Test the site locally from the project root:

```powershell
python -m http.server 8080
```

Open:

```text
http://localhost:8080/web/index.html
```
<hr>

## Troubleshooting

#### Backend says CORS_ORIGINS must be set

Add `CORS_ORIGINS` to `back_end/.env`. For local testing, use:

```text
CORS_ORIGINS=http://localhost:5000,http://127.0.0.1:5000
```

#### Backend health says database error

Check that PostgreSQL is running and `DATABASE_URL` points to an existing database.

#### Gemini is not configured

Add a valid `GEMINI_API_KEY` to `back_end/.env` locally or to Render environment variables in production.

#### Flutter cannot reach the backend

Use the right backend URL:

- Android emulator: `http://10.0.2.2:5000`
- Physical phone: `http://YOUR_COMPUTER_LAN_IP:5000`
- Render: `https://YOUR_RENDER_SERVICE.onrender.com`

Then rebuild or rerun the app after editing `front_end/.env`.

#### Google sign-in fails

Check that:

- `google-services.json` is in `front_end/android/app/`
- Google sign-in is enabled in Firebase Authentication
- The Android package name matches Firebase
- Your SHA-1 fingerprint is added to Firebase

#### Notifications do not show

On Android 13 or newer, allow notification permission when the app asks. Also make sure exact alarms are allowed for the app if your device blocks them by default.

## Git History (Including Past Commits with Vulnerabilities)

```text
a1b4648 (HEAD -> main, origin/main) HEAD@{0}: Branch: renamed refs/heads/temp-main to refs/heads/main
a1b4648 (HEAD -> main, origin/main) HEAD@{2}: commit (initial): chore: initial clean commit
5e5a0dd HEAD@{3}: Branch: renamed refs/heads/temp-main to refs/heads/main
5e5a0dd HEAD@{5}: commit (initial): chore: clean commit of V1 Zam:Medicine ReminderApp
03e4a22 HEAD@{6}: reset: moving to HEAD
03e4a22 HEAD@{7}: commit: chore: venv miscellaneous files untracked
1f1f264 HEAD@{8}: commit: refactor: ensures one request at a time
7288904 HEAD@{9}: commit (amend): refactor: fix gemini API services
9ffd31e HEAD@{10}: commit (amend): Your new and improved commit message
68b07b6 HEAD@{11}: commit: refactor: fix gemini API services
f8af52d HEAD@{12}: commit: chore: update .gitignore again
d975d94 HEAD@{13}: commit: chore: update .gitginore
7f1753a HEAD@{14}: commit: feat: Version 1.0 ReminderApp
8a6904e HEAD@{15}: reset: moving to HEAD~1
5e356da HEAD@{16}: pull origin main: Merge made by the 'ort' strategy.
8a6904e HEAD@{17}: commit: chore: remove readme.md
65b90b9 HEAD@{18}: Branch: renamed refs/heads/fresh-start to refs/heads/main
65b90b9 HEAD@{20}: commit (initial): Initial clean commit
337e45e HEAD@{21}: commit: chore: remove generated tracked files github
2bd71ca HEAD@{22}: commit: chore: fix gitignore duplicates
339c3f3 HEAD@{23}: commit: chore: fix files conflicts
14da8f1 HEAD@{24}: commit: chore: move flutter to front_end folder and add backend folder for flask API
d2abce0 HEAD@{25}: commit: chore: Boiler template for reminder-app
70e46d6 HEAD@{26}: commit (initial): Initial Commit
```