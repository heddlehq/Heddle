@echo off
rem The `heddle` command on Windows. Runs in the foreground.
setlocal

set "ROOT=%~dp0"
if not defined HEDDLE_HOME for %%I in ("%ROOT%..") do set "HEDDLE_HOME=%%~fI"
rem The release cookie is the same in every download, so no distribution at all.
set "RELEASE_DISTRIBUTION=none"

set "COMMAND=%~1"
if "%COMMAND%"=="" set "COMMAND=start"

if /i "%COMMAND%"=="start" (
  call "%ROOT%bin\heddle.bat" start
  rem Ctrl+C kills the VM before it can stop the database.
  "%ROOT%pgsql\bin\pg_ctl.exe" -D "%HEDDLE_HOME%\data\postgres" -m fast -w stop >nul 2>&1
  exit /b 0
)
if /i "%COMMAND%"=="stop" (
  "%ROOT%pgsql\bin\pg_ctl.exe" -D "%HEDDLE_HOME%\data\postgres" -m fast -w stop
  exit /b %ERRORLEVEL%
)
if /i "%COMMAND%"=="version" (
  type "%ROOT%VERSION"
  exit /b 0
)

echo Usage: heddle [start^|stop^|version] 1>&2
exit /b 1
