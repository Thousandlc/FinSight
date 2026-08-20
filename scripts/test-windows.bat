@echo off
call "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set "PATH=%LOCALAPPDATA%\Programs\Swift\Runtimes\6.3.3\usr\bin;%LOCALAPPDATA%\Programs\Swift\Toolchains\6.3.3+Asserts\usr\bin;%PATH%"
set "SDKROOT=%LOCALAPPDATA%\Programs\Swift\Platforms\6.3.3\Windows.platform\Developer\SDKs\Windows.sdk"
cd /d "%~dp0.."
echo Running Foundation tests...
swift test --filter YoushuFoundationTests
if errorlevel 1 exit /b %ERRORLEVEL%
echo Running Domain tests...
swift test --filter YoushuDomainTests
if errorlevel 1 exit /b %ERRORLEVEL%
echo Running Data tests...
swift test --filter YoushuDataTests
if errorlevel 1 exit /b %ERRORLEVEL%
echo Running AI tests...
swift test --filter YoushuAITests
exit /b %ERRORLEVEL%
