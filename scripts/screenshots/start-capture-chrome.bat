@echo off
REM ---------------------------------------------------------------------------
REM Opens the Chrome that screenshot automation attaches to.
REM
REM Double-click this whenever the capture window is not already open. You stay
REM signed in between launches -- the profile lives in the folder below -- so
REM this normally just opens a window and nothing else is needed.
REM
REM Sign in to HCP Terraform (and the AWS console, if you want console shots
REM through this browser) the FIRST time only. See START_CHROME.md for why this
REM exists: Google refuses to authenticate inside an automation-launched
REM browser, so the browser has to be a real one that we attach to afterwards.
REM
REM The profile is deliberately separate from your everyday Chrome: Chrome
REM refuses --remote-debugging-port on the default profile, and automation
REM should never touch your normal bookmarks, cookies or sessions.
REM ---------------------------------------------------------------------------

set "CHROME=C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" set "CHROME=C:\Program Files\Google\Chrome\Application\chrome.exe"

if not exist "%CHROME%" (
  echo Could not find chrome.exe in either Program Files location.
  echo Edit this file and set CHROME to the right path.
  pause
  exit /b 1
)

start "" "%CHROME%" ^
  --remote-debugging-port=9222 ^
  --user-data-dir="%USERPROFILE%\chrome-automation-profile"

echo.
echo Capture Chrome starting on port 9222.
echo First run only: sign in to HCP Terraform in that window.
echo Leave it open while screenshots are being taken.
echo.
