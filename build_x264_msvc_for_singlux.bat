@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM Build custom Singlux x264 with MSVC for FFmpeg --toolchain=msvc.
REM
REM Goal output:
REM   C:\Users\long\Desktop\singlux-x264\x264\build-msvc-ffmpeg\include\x264.h
REM   C:\Users\long\Desktop\singlux-x264\x264\build-msvc-ffmpeg\lib\libx264.lib
REM   C:\Users\long\Desktop\singlux-x264\x264\build-msvc-ffmpeg\lib\pkgconfig\x264.pc
REM
REM This script does NOT build FFmpeg. It only prepares x264 for the
REM existing MSVC FFmpeg build flow.
REM ============================================================

set "VS_VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"
set "VS_BIN=C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Tools\MSVC\14.29.30133\bin\Hostx64\x64"
set "VS_BIN_MSYS=/c/Program Files (x86)/Microsoft Visual Studio/2019/Community/VC/Tools/MSVC/14.29.30133/bin/Hostx64/x64"
set "MSYS_BASH=C:\msys64\usr\bin\bash.exe"

set "X264_SOURCE=C:\Users\long\Desktop\singlux-x264\x264"
set "X264_SOURCE_MSYS=/c/Users/long/Desktop/singlux-x264/x264"
set "X264_PREFIX=C:\Users\long\Desktop\singlux-x264\x264\build-msvc-ffmpeg"
set "X264_PREFIX_MSYS=/c/Users/long/Desktop/singlux-x264/x264/build-msvc-ffmpeg"
set "MAKE_JOBS=8"

REM Some x264 builds need nasm/yasm. If unavailable, configure will disable asm.
REM Keeping asm enabled is preferred, but the script falls back to --disable-asm
REM only if the first configure/build path fails.

if /i "%~1"=="clean" goto CLEAN_ONLY

echo.
echo [CHECK] Visual Studio vcvars64
if not exist "!VS_VCVARS!" (
  echo [ERROR] Cannot find VS2019 vcvars64.bat:
  echo         !VS_VCVARS!
  exit /b 1
)

echo.
echo [CHECK] MSVC bin
if not exist "!VS_BIN!\cl.exe" (
  echo [ERROR] Cannot find cl.exe:
  echo         !VS_BIN!\cl.exe
  exit /b 1
)
if not exist "!VS_BIN!\lib.exe" (
  echo [ERROR] Cannot find lib.exe:
  echo         !VS_BIN!\lib.exe
  exit /b 1
)
if not exist "!VS_BIN!\link.exe" (
  echo [ERROR] Cannot find link.exe:
  echo         !VS_BIN!\link.exe
  exit /b 1
)

echo.
echo [CHECK] MSYS bash
if not exist "!MSYS_BASH!" (
  echo [ERROR] Cannot find MSYS bash:
  echo         !MSYS_BASH!
  exit /b 1
)

echo.
echo [CHECK] x264 source
if not exist "!X264_SOURCE!\x264.h" (
  echo [ERROR] Cannot find x264 source:
  echo         !X264_SOURCE!\x264.h
  exit /b 1
)

echo.
echo [ENV] Loading VS2019 x64 environment...
call "!VS_VCVARS!"
if errorlevel 1 (
  echo [ERROR] Failed to load VS2019 environment.
  exit /b 1
)

set "PATH=!VS_BIN!;!PATH!"

echo.
echo [CHECK] MSYS sees cl/link/lib
"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; which cl; which link; which lib; cl 2>&1 | head -n 2"
if errorlevel 1 (
  echo [ERROR] MSYS cannot see cl/link/lib.
  exit /b 1
)

echo.
echo [CHECK] Singlux x264 patch exists in source
"!MSYS_BASH!" -lc "cd '!X264_SOURCE_MSYS!' && grep -R 'singlux-anchor-ref\|singlux-poc-lsb-bits' -n x264.h common/base.c x264.c encoder/encoder.c encoder/set.c"
if errorlevel 1 (
  echo [ERROR] Singlux x264 patch was not found in this source tree.
  echo         Expected singlux-anchor-ref and singlux-poc-lsb-bits.
  exit /b 1
)

echo.
echo ============================================================
echo [1/5] Clean old x264 build/install output
echo ============================================================

if exist "!X264_PREFIX!" (
  echo [CLEAN] Removing old prefix:
  echo         !X264_PREFIX!
  rmdir /s /q "!X264_PREFIX!"
  if errorlevel 1 exit /b 1
)

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!X264_SOURCE_MSYS!' && make distclean 2>/dev/null || true"
if errorlevel 1 (
  echo [ERROR] x264 distclean failed.
  exit /b 1
)

echo.
echo ============================================================
echo [2/5] Configure x264 for MSVC static library
echo ============================================================

REM We disable CLI here because the purpose is linking FFmpeg to libx264.
REM CLI testing was already done with the MinGW x264.exe path.
"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!X264_SOURCE_MSYS!' && CC=cl ./configure --prefix='!X264_PREFIX_MSYS!' --host=x86_64-w64-mingw32 --enable-static --disable-cli"
if errorlevel 1 (
  echo [WARN] x264 configure with asm/default flags failed.
  echo [WARN] Retrying with --disable-asm for maximum MSVC compatibility...
  "!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!X264_SOURCE_MSYS!' && make distclean 2>/dev/null || true && CC=cl ./configure --prefix='!X264_PREFIX_MSYS!' --host=x86_64-w64-mingw32 --enable-static --disable-cli --disable-asm"
  if errorlevel 1 (
    echo [ERROR] x264 configure failed, even with --disable-asm.
    echo         Check config.log in:
    echo         !X264_SOURCE!
    exit /b 1
  )
)

echo.
echo ============================================================
echo [3/5] Build and install x264 static library
echo ============================================================

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!X264_SOURCE_MSYS!' && make -j!MAKE_JOBS! && make install"
if errorlevel 1 (
  echo [ERROR] x264 build/install failed.
  exit /b 1
)

echo.
echo ============================================================
echo [4/5] Normalize library name for FFmpeg
echo ============================================================

if exist "!X264_PREFIX!\lib\libx264.lib" (
  echo [OK] Found libx264.lib
) else if exist "!X264_PREFIX!\lib\x264.lib" (
  echo [COPY] x264.lib -^> libx264.lib
  copy /Y "!X264_PREFIX!\lib\x264.lib" "!X264_PREFIX!\lib\libx264.lib" >nul
  if errorlevel 1 exit /b 1
) else if exist "!X264_SOURCE!\libx264.lib" (
  echo [COPY] source libx264.lib -^> prefix lib
  if not exist "!X264_PREFIX!\lib" mkdir "!X264_PREFIX!\lib"
  copy /Y "!X264_SOURCE!\libx264.lib" "!X264_PREFIX!\lib\libx264.lib" >nul
  if errorlevel 1 exit /b 1
) else if exist "!X264_SOURCE!\x264.lib" (
  echo [COPY] source x264.lib -^> prefix libx264.lib
  if not exist "!X264_PREFIX!\lib" mkdir "!X264_PREFIX!\lib"
  copy /Y "!X264_SOURCE!\x264.lib" "!X264_PREFIX!\lib\libx264.lib" >nul
  if errorlevel 1 exit /b 1
) else (
  echo [ERROR] Cannot find x264 static library.
  echo         Checked:
  echo           !X264_PREFIX!\lib\libx264.lib
  echo           !X264_PREFIX!\lib\x264.lib
  echo           !X264_SOURCE!\libx264.lib
  echo           !X264_SOURCE!\x264.lib
  exit /b 1
)

if not exist "!X264_PREFIX!\include\x264.h" (
  echo [ERROR] Missing installed x264.h:
  echo         !X264_PREFIX!\include\x264.h
  exit /b 1
)

if not exist "!X264_PREFIX!\lib\pkgconfig\x264.pc" (
  echo [WARN] Missing x264.pc. Creating minimal pkg-config file for diagnostics.
  if not exist "!X264_PREFIX!\lib\pkgconfig" mkdir "!X264_PREFIX!\lib\pkgconfig"
  >"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo prefix=/c/Users/long/Desktop/singlux-x264/x264/build-msvc-ffmpeg
  >>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo exec_prefix=${prefix}
  >>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo libdir=${prefix}/lib
  >>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo includedir=${prefix}/include
  >>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo.
  >>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo Name: x264
  >>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo Description: H.264 encoder
  >>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo Version: 0.165
  >>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo Libs: -L${libdir} -lx264
  >>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo Cflags: -I${includedir}
)

echo.
echo ============================================================
echo [5/5] Validate installed x264 for FFmpeg
echo ============================================================

echo [CHECK] Installed files
if not exist "!X264_PREFIX!\include\x264.h" exit /b 1
if not exist "!X264_PREFIX!\lib\libx264.lib" exit /b 1
if not exist "!X264_PREFIX!\lib\pkgconfig\x264.pc" exit /b 1

echo.
echo [CHECK] Installed x264.h contains Singlux params
"!MSYS_BASH!" -lc "grep -n 'b_singlux_anchor_ref\|i_singlux_poc_lsb_bits' '!X264_PREFIX_MSYS!/include/x264.h'"
if errorlevel 1 (
  echo [ERROR] Installed x264.h does not contain Singlux params.
  exit /b 1
)

echo.
echo [CHECK] Static library exists
"!MSYS_BASH!" -lc "ls -lh '!X264_PREFIX_MSYS!/lib/libx264.lib' '!X264_PREFIX_MSYS!/lib/pkgconfig/x264.pc'"
if errorlevel 1 exit /b 1

echo.
echo ============================================================
echo [DONE] x264 MSVC static library is ready.
echo.
echo Include:
echo   !X264_PREFIX!\include
echo Library path:
echo   !X264_PREFIX!\lib
echo Library name:
echo   libx264.lib
echo.
echo Use these in FFmpeg --toolchain=msvc configure:
echo   --enable-libx264
echo   --extra-cflags='-I/c/Users/long/Desktop/singlux-x264/x264/build-msvc-ffmpeg/include ...'
echo   --extra-ldflags='-libpath:C:/Users/long/Desktop/singlux-x264/x264/build-msvc-ffmpeg/lib ...'
echo   --extra-libs='libx264.lib libx265.lib ucrt.lib vcruntime.lib msvcrt.lib oldnames.lib'
echo ============================================================

exit /b 0

:CLEAN_ONLY
echo [CLEAN] Removing x264 MSVC install prefix only:
echo         !X264_PREFIX!
if exist "!X264_PREFIX!" rmdir /s /q "!X264_PREFIX!"
exit /b 0
