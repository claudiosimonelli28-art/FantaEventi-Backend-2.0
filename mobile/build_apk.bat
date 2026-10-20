@echo off
cd /d "%~dp0"
flutter build apk --release --dart-define-from-file=app_config.json %*
