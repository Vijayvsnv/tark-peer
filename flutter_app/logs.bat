@echo off
REM Tark Peer - App Logs Only
REM Ye script SIRF tarkpeer app ke logs dikhata hai (PID-filtered).
REM Samsung, Google, Jio, Zomato, aur baaki phone ka noise ZERO.

echo.
echo ============================================
echo   TARK PEER - APP LOGS ONLY
echo   Sirf tumhari app ke logs (PID-filtered)
echo   Phone ka baaki noise ZERO hai
echo ============================================
echo.
echo Waiting for Tark Peer app to start on device...
echo (App khulne pe automatically logs aane lagenge)
echo.

REM Purane logs clear karo
adb logcat -c

REM App ka PID milne tak wait karo (poll every 2s)
:wait_for_pid
for /f "tokens=*" %%i in ('adb shell pidof com.tarkpeer.tark_peer 2^>nul') do set APP_PID=%%i
if "%APP_PID%"=="" (
    timeout /t 2 /nobreak >nul
    goto wait_for_pid
)

echo App detected! PID = %APP_PID%
echo Streaming logs... (Ctrl+C se stop karo)
echo ============================================
echo.

REM PID + tag filter:
REM   flutter:V  -> saare Dart/Flutter output (I/W/E)
REM   *:E        -> sirf ERROR level baaki sab tags ka (crash catch ho jayega)
REM   *:S        -> silence baaki sab (VRI, ImeTracker, keyboard, view render — sab hide)
adb logcat --pid=%APP_PID% flutter:V AndroidRuntime:E DEBUG:E System.err:E *:S
