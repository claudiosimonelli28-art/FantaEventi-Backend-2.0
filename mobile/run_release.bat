@echo off
cd /d "%~dp0"
flutter run --release --dart-define-from-file=app_config.json %*
