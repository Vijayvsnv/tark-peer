@echo off
REM Tark Peer - Clean Dev Runner
REM Ye script 2 windows kholta hai:
REM   1. Ye window = flutter run (hot reload ke liye - r/R/q keys)
REM   2. Naya window = SIRF Tark Peer app ke logs (PID-filtered, phone noise gayab)

echo.
echo ============================================
echo   Tark Peer - Starting Dev Environment
echo ============================================
echo.
echo Naya window kholega jisme SIRF tumhari app ke logs dikhenge.
echo Is window me flutter run chalega (hot reload ke liye).
echo.
echo Keys:
echo   r  = Hot reload
echo   R  = Hot restart
echo   q  = Quit
echo.

REM Purane logs clear karo
adb logcat -c

REM Naya window kholo jo PID-filtered logs dikhaye
start "Tark Peer - App Logs Only" cmd /k "logs.bat"

REM Wait 1 sec so log window opens first
timeout /t 1 /nobreak >nul

REM Is window me flutter run chalao (hot reload keys work karne ke liye)
flutter run -d RZCX51MN2KP
