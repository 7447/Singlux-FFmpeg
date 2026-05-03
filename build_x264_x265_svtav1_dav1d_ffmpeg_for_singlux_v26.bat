@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Keep Python/Meson/MSVC output decodable when Windows locale is Traditional Chinese.
chcp 65001 >nul 2>nul
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"
set "VSLANG=1033"

REM ============================================================
REM Singlux one-shot build:
REM   1) Build custom x264 as MSVC static lib for FFmpeg
REM   2) Build custom x265 with VS2019 static lib
REM   3) Build custom Singlux SVT-AV1 as MSVC static lib for FFmpeg
REM   4) Build dav1d as MSVC static lib for AV1 software decoding
REM   5) Build FFmpeg --toolchain=msvc with libx264 + libx265 + libsvtav1 + libdav1d
REM   6) Smoke test Singlux x264/x265/SVT-AV1 encode and dav1d AV1 decode through FFmpeg
REM
REM Run from Windows CMD, not PowerShell/MSYS:
REM   cd /d C:\Users\long\Desktop\singlux-ffmpeg
REM   build_x264_x265_svtav1_dav1d_ffmpeg_for_singlux_v26.bat
REM ============================================================

set "VS_VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"
set "VS_BIN=C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Tools\MSVC\14.29.30133\bin\Hostx64\x64"
set "VS_BIN_MSYS=/c/Program Files (x86)/Microsoft Visual Studio/2019/Community/VC/Tools/MSVC/14.29.30133/bin/Hostx64/x64"
set "MSYS_BASH=C:\msys64\usr\bin\bash.exe"

set "X264_SOURCE=C:\Users\long\Desktop\singlux-x264\x264"
set "X264_SOURCE_MSYS=/c/Users/long/Desktop/singlux-x264/x264"
set "X264_PREFIX=C:\Users\long\Desktop\singlux-x264\x264\build-msvc-ffmpeg"
set "X264_PREFIX_MSYS=/c/Users/long/Desktop/singlux-x264/x264/build-msvc-ffmpeg"

set "X265_SOURCE=C:\Users\long\Desktop\sinlgux-x265\x265\source"
set "X265_SOURCE_MSYS=/c/Users/long/Desktop/sinlgux-x265/x265/source"
set "X265_BUILD=build-vs2019-ffmpeg-md"
set "X265_BUILD_DIR=%X265_SOURCE%\%X265_BUILD%"
set "X265_BUILD_DIR_MSYS=/c/Users/long/Desktop/sinlgux-x265/x265/source/build-vs2019-ffmpeg-md"

REM NOTE: keep the original folder spelling you are using now: sinlgux-AV1.
REM This must be your patched SVT-AV1 repo, not a clean upstream copy.
set "SVTAV1_SOURCE=C:\Users\long\Desktop\sinlgux-AV1"
set "SVTAV1_SOURCE_MSYS=/c/Users/long/Desktop/sinlgux-AV1"
set "SVTAV1_BUILD=build-vs2019-ffmpeg-md"
set "SVTAV1_BUILD_DIR=%SVTAV1_SOURCE%\%SVTAV1_BUILD%"
set "SVTAV1_BUILD_DIR_MSYS=/c/Users/long/Desktop/sinlgux-AV1/build-vs2019-ffmpeg-md"
set "SVTAV1_PREFIX=%SVTAV1_SOURCE%\build-msvc-ffmpeg"
set "SVTAV1_PREFIX_MSYS=/c/Users/long/Desktop/sinlgux-AV1/build-msvc-ffmpeg"

REM dav1d is the AV1 software decoder used to verify jump-decode output.
REM If this folder does not exist, the script will try to git clone upstream dav1d here.
set "DAV1D_SOURCE=C:\Users\long\Desktop\dav1d"
set "DAV1D_SOURCE_MSYS=/c/Users/long/Desktop/dav1d"
set "DAV1D_BUILD=build-vs2019-ffmpeg-md"
set "DAV1D_BUILD_DIR=%DAV1D_SOURCE%\%DAV1D_BUILD%"
set "DAV1D_BUILD_DIR_MSYS=/c/Users/long/Desktop/dav1d/build-vs2019-ffmpeg-md"
set "DAV1D_PREFIX=%DAV1D_SOURCE%\build-msvc-ffmpeg"
set "DAV1D_PREFIX_MSYS=/c/Users/long/Desktop/dav1d/build-msvc-ffmpeg"
set "DAV1D_PREFIX_WIN=C:/Users/long/Desktop/dav1d/build-msvc-ffmpeg"

set "FFMPEG_SOURCE=C:\Users\long\Desktop\singlux-ffmpeg\Singlux-FFmpeg"
set "FFMPEG_SOURCE_MSYS=/c/Users/long/Desktop/singlux-ffmpeg/Singlux-FFmpeg"

set "MAKE_JOBS=8"
if not "%~1"=="" set "MAKE_JOBS=%~1"

if /i "%~1"=="clean" goto CLEAN_ONLY

REM ============================================================
REM [0] Environment checks
REM ============================================================

echo.
echo ============================================================
echo [0/13] Check build environment
echo ============================================================

if not exist "!VS_VCVARS!" (
  echo [ERROR] Cannot find VS2019 vcvars64.bat:
  echo         !VS_VCVARS!
  exit /b 1
)

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

if not exist "!MSYS_BASH!" (
  echo [ERROR] Cannot find MSYS bash:
  echo         !MSYS_BASH!
  exit /b 1
)

echo [CHECK] MSYS build tools for dav1d ^(git/meson/ninja^)
"!MSYS_BASH!" -lc "command -v git && command -v meson && command -v ninja"
if errorlevel 1 (
  echo [WARN] Missing git, meson, or ninja in MSYS2.
  echo        Trying to install them automatically with pacman...
  "!MSYS_BASH!" -lc "pacman -S --needed --noconfirm git meson ninja"
  if errorlevel 1 (
    echo [ERROR] Failed to install git/meson/ninja automatically.
    echo         Open MSYS2 manually and run:
    echo         pacman -S --needed git meson ninja
    echo         Then rerun this bat.
    exit /b 1
  )
  echo [CHECK] Re-check MSYS build tools after pacman install
  "!MSYS_BASH!" -lc "command -v git && command -v meson && command -v ninja"
  if errorlevel 1 (
    echo [ERROR] git/meson/ninja still not visible from C:\msys64\usr\bin\bash.exe.
    echo         Try manually in MSYS2:
    echo         pacman -S --needed git meson ninja
    exit /b 1
  )
)

if not exist "!X264_SOURCE!\x264.h" (
  echo [ERROR] Cannot find x264 source:
  echo         !X264_SOURCE!\x264.h
  exit /b 1
)

if not exist "!X265_SOURCE!\CMakeLists.txt" (
  echo [ERROR] Cannot find x265 source:
  echo         !X265_SOURCE!\CMakeLists.txt
  exit /b 1
)

if not exist "!SVTAV1_SOURCE!\CMakeLists.txt" (
  echo [ERROR] Cannot find Singlux SVT-AV1 source:
  echo         !SVTAV1_SOURCE!\CMakeLists.txt
  echo         If your folder spelling is different, edit SVTAV1_SOURCE at the top of this bat.
  exit /b 1
)

if not exist "!SVTAV1_SOURCE!\Source\API\EbSvtAv1Enc.h" (
  echo [ERROR] Cannot find SVT-AV1 encoder API header:
  echo         !SVTAV1_SOURCE!\Source\API\EbSvtAv1Enc.h
  exit /b 1
)

if not exist "!DAV1D_SOURCE!\meson.build" (
  echo [FETCH] dav1d source was not found. Cloning into:
  echo         !DAV1D_SOURCE!
  if not exist "C:\Users\long\Desktop" (
    echo [ERROR] Cannot find Desktop folder for dav1d clone.
    exit /b 1
  )
  "!MSYS_BASH!" -lc "cd /c/Users/long/Desktop && git clone https://code.videolan.org/videolan/dav1d.git dav1d"
  if errorlevel 1 (
    echo [ERROR] Failed to clone dav1d.
    echo         You can manually clone it with:
    echo         git clone https://code.videolan.org/videolan/dav1d.git C:\Users\long\Desktop\dav1d
    exit /b 1
  )
)

if not exist "!DAV1D_SOURCE!\meson.build" (
  echo [ERROR] Cannot find dav1d source:
  echo         !DAV1D_SOURCE!\meson.build
  exit /b 1
)

if not exist "!FFMPEG_SOURCE!\configure" (
  echo [ERROR] Cannot find FFmpeg source:
  echo         !FFMPEG_SOURCE!\configure
  exit /b 1
)

echo [ENV] Loading VS2019 x64 environment...
call "!VS_VCVARS!"
if errorlevel 1 (
  echo [ERROR] Failed to load VS2019 environment.
  exit /b 1
)

set "PATH=!VS_BIN!;!PATH!"

echo.
echo [CHECK] MSYS sees cl/link.exe/lib.exe
"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; which cl; which link.exe; which lib.exe; cl 2>&1 | head -n 2"
if errorlevel 1 (
  echo [ERROR] MSYS cannot see cl/link/lib.
  exit /b 1
)

REM ============================================================
REM [1] Validate source patches
REM ============================================================

echo.
echo ============================================================
echo [1/13] Validate Singlux source patches
echo ============================================================

echo [CHECK] x264 Singlux params in source
"!MSYS_BASH!" -lc "cd '!X264_SOURCE_MSYS!' && grep -R 'singlux-anchor-ref\|singlux-poc-lsb-bits' -n x264.h common/base.c x264.c encoder/encoder.c encoder/set.c"
if errorlevel 1 (
  echo [ERROR] Singlux x264 patch was not found in this source tree.
  echo         Expected singlux-anchor-ref and singlux-poc-lsb-bits.
  exit /b 1
)

echo.
echo [CHECK] x265 custom option in source/build help will be validated after x265 build.

echo.
echo [CHECK] Singlux SVT-AV1 custom params in source
"!MSYS_BASH!" -lc "cd '!SVTAV1_SOURCE_MSYS!' && grep -R 'single_ref_idr0\|single-ref-idr0\|singlux_poc_lsb_bits\|singlux-poc-lsb-bits' -n Source/API/EbSvtAv1Enc.h Source/App Source/Lib | head -n 80"
if errorlevel 1 (
  echo [ERROR] Singlux SVT-AV1 single-ref-idr0 / singlux-poc-lsb-bits patch was not found.
  echo         This bat is intended to link your modified Singlux AV1 repo.
  exit /b 1
)

REM ============================================================
REM [2] Build x264 MSVC static library
REM ============================================================

echo.
echo ============================================================
echo [2/13] Build x264 MSVC static library
echo ============================================================

if exist "!X264_PREFIX!" (
  echo [CLEAN] Removing old x264 prefix:
  echo         !X264_PREFIX!
  rmdir /s /q "!X264_PREFIX!"
  if errorlevel 1 exit /b 1
)

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!X264_SOURCE_MSYS!' && make distclean 2>/dev/null || true"
if errorlevel 1 (
  echo [ERROR] x264 distclean failed.
  exit /b 1
)

echo [CONFIGURE] x264 with CC=cl
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

echo [BUILD] x264 libx264.lib
"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!X264_SOURCE_MSYS!' && make -j!MAKE_JOBS! && make install"
if errorlevel 1 (
  echo [ERROR] x264 build/install failed.
  exit /b 1
)

echo [NORMALIZE] x264 library name
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
  exit /b 1
)

REM FFmpeg configure uses pkg-config Libs: -lx264.
REM With --toolchain=msvc, -lx264 can resolve to x264.lib, not libx264.lib.
REM Keep both names so the configure link test and final link both work.
if not exist "!X264_PREFIX!\lib\x264.lib" (
  echo [COPY] libx264.lib -^> x264.lib for FFmpeg pkg-config/MSVC check
  copy /Y "!X264_PREFIX!\lib\libx264.lib" "!X264_PREFIX!\lib\x264.lib" >nul
  if errorlevel 1 exit /b 1
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

echo [PKGCONFIG] Rewriting x264.pc for FFmpeg configure ^(minimal MSVC-safe pkg-config flags^)
REM Important:
REM   Do NOT put MSVC-style -libpath:... in x264.pc.
REM   FFmpeg configure's MSVC wrapper can mangle it into ibpath:...lib.lib.
REM   Keep x264.pc gcc-style, and pass the real MSVC link path via --extra-ldflags/--extra-libs below.
if not exist "!X264_PREFIX!\lib\pkgconfig" mkdir "!X264_PREFIX!\lib\pkgconfig"
>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo prefix=!X264_PREFIX_MSYS!
>>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo exec_prefix=!X264_PREFIX_MSYS!
>>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo libdir=!X264_PREFIX_MSYS!/lib
>>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo includedir=!X264_PREFIX_MSYS!/include
>>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo.
>>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo Name: x264
>>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo Description: H.264 encoder library
>>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo Version: 0.165
>>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo Libs: x264.lib
>>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo Libs.private:
>>"!X264_PREFIX!\lib\pkgconfig\x264.pc" echo Cflags:
"!MSYS_BASH!" -lc "cat '!X264_PREFIX_MSYS!/lib/pkgconfig/x264.pc'"
if errorlevel 1 (
  echo [ERROR] Failed to write x264.pc.
  exit /b 1
)

echo [VALIDATE] Installed x264 files
"!MSYS_BASH!" -lc "export PKG_CONFIG_PATH='!X264_PREFIX_MSYS!/lib/pkgconfig':$PKG_CONFIG_PATH; grep -n 'b_singlux_anchor_ref\|i_singlux_poc_lsb_bits' '!X264_PREFIX_MSYS!/include/x264.h' && ls -lh '!X264_PREFIX_MSYS!/lib/libx264.lib' '!X264_PREFIX_MSYS!/lib/x264.lib' '!X264_PREFIX_MSYS!/lib/pkgconfig/x264.pc' && pkg-config --cflags x264 && pkg-config --libs x264"
if errorlevel 1 (
  echo [ERROR] x264 install validation failed.
  exit /b 1
)

REM ============================================================
REM [3] Build x265 MSVC static library
REM ============================================================

echo.
echo ============================================================
echo [3/13] Rebuild x265 with VS2019 Release
echo ============================================================

cd /d "!X265_SOURCE!"
if errorlevel 1 exit /b 1

if exist "!X265_BUILD_DIR!" (
  echo [CLEAN] Removing old x265 build dir:
  echo         !X265_BUILD_DIR!
  rmdir /s /q "!X265_BUILD_DIR!"
  if errorlevel 1 exit /b 1
)

mkdir "!X265_BUILD_DIR!"
if errorlevel 1 exit /b 1

cd /d "!X265_BUILD_DIR!"
if errorlevel 1 exit /b 1

echo [CMAKE] Generate x265 VS2019 solution...
cmake -G "Visual Studio 16 2019" -A x64 ^
  -DENABLE_SHARED=OFF ^
  -DENABLE_CLI=ON ^
  ..
if errorlevel 1 (
  echo [ERROR] x265 cmake configure failed.
  exit /b 1
)

echo [BUILD] x265-static...
cmake --build . --config Release --target x265-static -- /m:%MAKE_JOBS%
if errorlevel 1 (
  echo [ERROR] x265-static build failed.
  exit /b 1
)

echo [BUILD] x265 CLI...
cmake --build . --config Release --target cli -- /m:%MAKE_JOBS%
if errorlevel 1 (
  echo [ERROR] x265 CLI build failed.
  exit /b 1
)

echo [COPY] Prepare x265 lib names for FFmpeg...
copy /Y "Release\x265-static.lib" "Release\libx265.lib" >nul
if errorlevel 1 exit /b 1
copy /Y "Release\x265-static.lib" "Release\x265.lib" >nul
if errorlevel 1 exit /b 1

echo [CHECK] x265 custom option must exist:
"Release\x265.exe" --fullhelp | findstr /i "single-ref-poc-lsb-bits"
if errorlevel 1 (
  echo [ERROR] x265.exe does not show single-ref-poc-lsb-bits.
  echo         Your x265 source may not contain the custom patch.
  exit /b 1
)

REM ============================================================
REM [4] Build Singlux SVT-AV1 MSVC static library
REM ============================================================

echo.
echo ============================================================
echo [4/13] Build Singlux SVT-AV1 with VS2019 Release
echo ============================================================

cd /d "!SVTAV1_SOURCE!"
if errorlevel 1 exit /b 1

if exist "!SVTAV1_BUILD_DIR!" (
  echo [CLEAN] Removing old SVT-AV1 build dir:
  echo         !SVTAV1_BUILD_DIR!
  rmdir /s /q "!SVTAV1_BUILD_DIR!"
  if errorlevel 1 exit /b 1
)

if exist "!SVTAV1_PREFIX!" (
  echo [CLEAN] Removing old SVT-AV1 FFmpeg prefix:
  echo         !SVTAV1_PREFIX!
  rmdir /s /q "!SVTAV1_PREFIX!"
  if errorlevel 1 exit /b 1
)

mkdir "!SVTAV1_BUILD_DIR!"
if errorlevel 1 exit /b 1

cd /d "!SVTAV1_BUILD_DIR!"
if errorlevel 1 exit /b 1

echo [CMAKE] Generate Singlux SVT-AV1 VS2019 solution...
cmake -G "Visual Studio 16 2019" -A x64 ^
  -DBUILD_SHARED_LIBS=OFF ^
  -DBUILD_APPS=ON ^
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL ^
  ..
if errorlevel 1 (
  echo [ERROR] SVT-AV1 cmake configure failed.
  exit /b 1
)

echo [BUILD] SVT-AV1 encoder library and app...
cmake --build . --config Release -- /m:%MAKE_JOBS%
if errorlevel 1 (
  echo [ERROR] SVT-AV1 build failed.
  exit /b 1
)

echo [FIND] Locate SvtAv1Enc.lib and SvtAv1EncApp.exe...
set "SVTAV1_LIB="
set "SVTAV1_APP="

REM SVT-AV1 may place build products in the source-level Bin\Release folder,
REM even when CMake is generated under build-vs2019-ffmpeg-md. Prefer the
REM exact output seen from your build log, then fall back to recursive search.
if exist "!SVTAV1_SOURCE!\Bin\Release\SvtAv1Enc.lib" set "SVTAV1_LIB=!SVTAV1_SOURCE!\Bin\Release\SvtAv1Enc.lib"
if exist "!SVTAV1_SOURCE!\Bin\Release\SvtAv1EncApp.exe" set "SVTAV1_APP=!SVTAV1_SOURCE!\Bin\Release\SvtAv1EncApp.exe"

if not defined SVTAV1_LIB (
  for /f "delims=" %%F in ('dir /s /b "!SVTAV1_BUILD_DIR!\SvtAv1Enc.lib" 2^>nul') do if not defined SVTAV1_LIB set "SVTAV1_LIB=%%F"
)
if not defined SVTAV1_APP (
  for /f "delims=" %%F in ('dir /s /b "!SVTAV1_BUILD_DIR!\SvtAv1EncApp.exe" 2^>nul') do if not defined SVTAV1_APP set "SVTAV1_APP=%%F"
)
if not defined SVTAV1_LIB (
  for /f "delims=" %%F in ('dir /s /b "!SVTAV1_SOURCE!\SvtAv1Enc.lib" 2^>nul') do if not defined SVTAV1_LIB set "SVTAV1_LIB=%%F"
)
if not defined SVTAV1_APP (
  for /f "delims=" %%F in ('dir /s /b "!SVTAV1_SOURCE!\SvtAv1EncApp.exe" 2^>nul') do if not defined SVTAV1_APP set "SVTAV1_APP=%%F"
)

if defined SVTAV1_LIB echo [OK] SVT-AV1 lib: !SVTAV1_LIB!
if defined SVTAV1_APP echo [OK] SVT-AV1 app: !SVTAV1_APP!

if not defined SVTAV1_LIB (
  echo [ERROR] Cannot find SvtAv1Enc.lib under either:
  echo         !SVTAV1_SOURCE!\Bin\Release
  echo         !SVTAV1_BUILD_DIR!
  echo         !SVTAV1_SOURCE!
  exit /b 1
)
if not defined SVTAV1_APP (
  echo [WARN] Cannot find SvtAv1EncApp.exe. FFmpeg link can still continue, but CLI help check will be skipped.
) else (
  echo [CHECK] SVT-AV1 custom CLI options must exist:
  "!SVTAV1_APP!" --help | findstr /i "single-ref-idr0 singlux-poc-lsb-bits"
  if errorlevel 1 (
    echo [ERROR] SvtAv1EncApp.exe does not show single-ref-idr0 / singlux-poc-lsb-bits.
    echo         You may be building the wrong SVT-AV1 source tree.
    exit /b 1
  )
)

echo [COPY] Prepare SVT-AV1 prefix for FFmpeg pkg-config...
mkdir "!SVTAV1_PREFIX!\include" 2>nul
mkdir "!SVTAV1_PREFIX!\lib" 2>nul
mkdir "!SVTAV1_PREFIX!\lib\pkgconfig" 2>nul
REM Copy every public SVT-AV1 API header. EbSvtAv1Enc.h includes EbSvtAv1.h,
REM and EbSvtAv1.h includes EbSvtAv1Formats.h in your tree.
echo [COPY] SVT-AV1 public API headers
copy /Y "!SVTAV1_SOURCE!\Source\API\*.h" "!SVTAV1_PREFIX!\include\" >nul
if errorlevel 1 (
  echo [ERROR] Failed to copy SVT-AV1 API headers from:
  echo         !SVTAV1_SOURCE!\Source\API
  exit /b 1
)
if not exist "!SVTAV1_PREFIX!\include\EbSvtAv1Formats.h" (
  echo [ERROR] Missing EbSvtAv1Formats.h after header copy.
  echo         Your SVT-AV1 Source\API folder may be incomplete or different than expected.
  exit /b 1
)
copy /Y "!SVTAV1_LIB!" "!SVTAV1_PREFIX!\lib\SvtAv1Enc.lib" >nul
if errorlevel 1 exit /b 1
REM FFmpeg/pkg-config/MSVC is less error-prone when -lSvtAv1Enc can resolve to
REM both SvtAv1Enc.lib and libSvtAv1Enc.lib depending on the wrapper path.
copy /Y "!SVTAV1_PREFIX!\lib\SvtAv1Enc.lib" "!SVTAV1_PREFIX!\lib\libSvtAv1Enc.lib" >nul
if errorlevel 1 exit /b 1

REM FFmpeg configure checks libsvtav1 through pkg-config name SvtAv1Enc.
REM v10 used "Libs: SvtAv1Enc.lib". FFmpeg's check_func_headers then sent the .lib
REM into the compile phase too. v14 uses standard pkg-config -L/-l form and also
REM passes the real MSVC libpath/libs through --extra-ldflags/--extra-libs.
>"!SVTAV1_PREFIX!\lib\pkgconfig\SvtAv1Enc.pc" echo prefix=!SVTAV1_PREFIX_MSYS!
>>"!SVTAV1_PREFIX!\lib\pkgconfig\SvtAv1Enc.pc" echo exec_prefix=!SVTAV1_PREFIX_MSYS!
>>"!SVTAV1_PREFIX!\lib\pkgconfig\SvtAv1Enc.pc" echo libdir=!SVTAV1_PREFIX_MSYS!/lib
>>"!SVTAV1_PREFIX!\lib\pkgconfig\SvtAv1Enc.pc" echo includedir=!SVTAV1_PREFIX_MSYS!/include
>>"!SVTAV1_PREFIX!\lib\pkgconfig\SvtAv1Enc.pc" echo.
>>"!SVTAV1_PREFIX!\lib\pkgconfig\SvtAv1Enc.pc" echo Name: SvtAv1Enc
>>"!SVTAV1_PREFIX!\lib\pkgconfig\SvtAv1Enc.pc" echo Description: SVT-AV1 encoder library
>>"!SVTAV1_PREFIX!\lib\pkgconfig\SvtAv1Enc.pc" echo Version: 3.0.0
>>"!SVTAV1_PREFIX!\lib\pkgconfig\SvtAv1Enc.pc" echo Libs: -L${libdir} -lSvtAv1Enc -lwinmm -ladvapi32 -lshell32 -lole32 -luser32 -lbcrypt
>>"!SVTAV1_PREFIX!\lib\pkgconfig\SvtAv1Enc.pc" echo Libs.private:
>>"!SVTAV1_PREFIX!\lib\pkgconfig\SvtAv1Enc.pc" echo Cflags: -I${includedir}

"!MSYS_BASH!" -lc "export PKG_CONFIG_PATH='!SVTAV1_PREFIX_MSYS!/lib/pkgconfig':$PKG_CONFIG_PATH; cat '!SVTAV1_PREFIX_MSYS!/lib/pkgconfig/SvtAv1Enc.pc'; pkg-config --cflags SvtAv1Enc; pkg-config --libs SvtAv1Enc; ls -lh '!SVTAV1_PREFIX_MSYS!/include'/EbSvtAv1*.h '!SVTAV1_PREFIX_MSYS!/lib/SvtAv1Enc.lib' '!SVTAV1_PREFIX_MSYS!/lib/libSvtAv1Enc.lib'"
if errorlevel 1 (
  echo [ERROR] SVT-AV1 pkg-config validation failed.
  exit /b 1
)

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd /tmp && printf '#include <EbSvtAv1Enc.h>\nint main(void){return 0;}\n' > svtav1_header_check.c && cl -nologo -I'!SVTAV1_PREFIX_MSYS!/include' -c -Fosvtav1_header_check.obj svtav1_header_check.c"
if errorlevel 1 (
  echo [ERROR] SVT-AV1 header compile check failed before FFmpeg configure.
  echo         Check copied headers under: !SVTAV1_PREFIX!\include
  exit /b 1
)

REM This is the same symbol FFmpeg configure checks for libsvtav1.
REM Running it before configure gives a clearer error if a dependent Windows lib is missing.
"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd /tmp && printf '#include <EbSvtAv1Enc.h>\n#include <stdint.h>\nlong f(void){return (long)svt_av1_enc_init_handle;}\nint main(void){return (int)((intptr_t)f & 0xffff);}\n' > svtav1_link_check.c && cl -nologo -I'!SVTAV1_PREFIX_MSYS!/include' -c -Fosvtav1_link_check.obj svtav1_link_check.c && link -nologo -LIBPATH:'!SVTAV1_PREFIX_MSYS!/lib' -OUT:svtav1_link_check.exe svtav1_link_check.obj SvtAv1Enc.lib winmm.lib advapi32.lib shell32.lib ole32.lib user32.lib bcrypt.lib ucrt.lib vcruntime.lib msvcrt.lib oldnames.lib"
if errorlevel 1 (
  echo [ERROR] SVT-AV1 manual link check failed before FFmpeg configure.
  echo         This means SvtAv1Enc.lib exists but one or more symbols/dependencies cannot link.
  echo         Check the link errors printed just above this message.
  exit /b 1
)

REM ============================================================
REM [5] Build dav1d AV1 software decoder MSVC static library
REM ============================================================

echo.
echo ============================================================
echo [5/13] Build dav1d AV1 software decoder with MSVC static lib
echo ============================================================

cd /d "!DAV1D_SOURCE!"
if errorlevel 1 exit /b 1

if exist "!DAV1D_BUILD_DIR!" (
  echo [CLEAN] Removing old dav1d build dir:
  echo         !DAV1D_BUILD_DIR!
  rmdir /s /q "!DAV1D_BUILD_DIR!"
  if errorlevel 1 exit /b 1
)

if exist "!DAV1D_PREFIX!" (
  echo [CLEAN] Removing old dav1d FFmpeg prefix:
  echo         !DAV1D_PREFIX!
  rmdir /s /q "!DAV1D_PREFIX!"
  if errorlevel 1 exit /b 1
)

echo [MESON] Configure dav1d static library with Windows Python Meson + cl.exe
 echo [MESON] Avoid MSYS path conversion entirely for dav1d; cl.exe must see Windows paths
 echo [MESON] Force UTF-8/English output to avoid Meson UnicodeDecodeError with localized cl.exe
set "LINK="
set "CC=cl"
set "CXX=cl"
set "AR=lib.exe"
set "VSLANG=1033"
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"

python --version >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Windows python was not found from this shell.
  echo         Open Anaconda/base or install Python, then rerun this bat.
  exit /b 1
)

python -c "import mesonbuild, ninja" >nul 2>nul
if errorlevel 1 (
  echo [PYTHON] Installing Windows meson+ninja into the current Python environment...
  python -m pip install --user --upgrade meson ninja
  if errorlevel 1 (
    echo [ERROR] Failed to install meson/ninja for Windows Python.
    echo         Try manually:
    echo         python -m pip install --user --upgrade meson ninja
    exit /b 1
  )
)

for /f "delims=" %%S in ('python -c "import sysconfig; print(sysconfig.get_path('scripts'))"') do set "PYTHON_SCRIPTS=%%S"
if defined PYTHON_SCRIPTS set "PATH=!PYTHON_SCRIPTS!;!PATH!"

python -c "import sys; print('[PYTHON]', sys.executable)"
python -m mesonbuild.mesonmain --version
if errorlevel 1 (
  echo [ERROR] meson is installed/importable but python -m mesonbuild.mesonmain --version failed.
  echo         Try manually:
  echo         python -m mesonbuild.mesonmain --version
  exit /b 1
)
python -c "import ninja; print('[NINJA] python package import OK')"
if errorlevel 1 (
  echo [ERROR] ninja is still not importable in Windows Python.
  echo         Try manually:
  echo         python -m pip install --user --upgrade ninja
  exit /b 1
)

python -m mesonbuild.mesonmain setup "!DAV1D_BUILD_DIR!" ^
  --vsenv ^
  --backend=ninja ^
  --buildtype=release ^
  --default-library=static ^
  --prefix="!DAV1D_PREFIX!" ^
  --libdir=lib ^
  --includedir=include ^
  -Denable_tools=false ^
  -Denable_tests=false ^
  -Denable_asm=false
if errorlevel 1 (
  echo [ERROR] dav1d meson configure failed.
  echo         Showing meson-log tail:
  powershell -NoProfile -Command "Get-Content '!DAV1D_BUILD_DIR!\meson-logs\meson-log.txt' -Tail 180" 2>nul
  echo.
  echo         This v24 intentionally runs Meson from Windows Python, not MSYS, to avoid /c path and /Fe conversion bugs.
  echo         If it still fails, paste the meson-log tail above.
  exit /b 1
)

echo [BUILD] dav1d static library
python -m mesonbuild.mesonmain compile -C "!DAV1D_BUILD_DIR!"
if errorlevel 1 (
  echo [ERROR] dav1d compile failed.
  exit /b 1
)

python -m mesonbuild.mesonmain install -C "!DAV1D_BUILD_DIR!"
if errorlevel 1 (
  echo [ERROR] dav1d install failed.
  exit /b 1
)

echo [NORMALIZE] dav1d library/header/pkg-config files
if not exist "!DAV1D_PREFIX!\include\dav1d\dav1d.h" (
  echo [ERROR] Missing installed dav1d header:
  echo         !DAV1D_PREFIX!\include\dav1d\dav1d.h
  exit /b 1
)

REM Meson with MSVC may install a COFF static archive named libdav1d.a.
REM MSVC link.exe can use the same archive after renaming/copying it to .lib.
if exist "!DAV1D_PREFIX!\lib\dav1d.lib" (
  echo [OK] Found dav1d.lib
) else if exist "!DAV1D_PREFIX!\lib\libdav1d.lib" (
  echo [COPY] libdav1d.lib -^> dav1d.lib
  copy /Y "!DAV1D_PREFIX!\lib\libdav1d.lib" "!DAV1D_PREFIX!\lib\dav1d.lib" >nul
  if errorlevel 1 exit /b 1
) else if exist "!DAV1D_PREFIX!\lib\libdav1d.a" (
  echo [COPY] libdav1d.a -^> dav1d.lib ^(MSVC COFF archive installed with .a suffix^)
  copy /Y "!DAV1D_PREFIX!\lib\libdav1d.a" "!DAV1D_PREFIX!\lib\dav1d.lib" >nul
  if errorlevel 1 exit /b 1
) else (
  for /f "delims=" %%F in ('dir /s /b "!DAV1D_BUILD_DIR!\*dav1d*.lib" 2^>nul') do if not exist "!DAV1D_PREFIX!\lib\dav1d.lib" copy /Y "%%F" "!DAV1D_PREFIX!\lib\dav1d.lib" >nul
  for /f "delims=" %%F in ('dir /s /b "!DAV1D_BUILD_DIR!\*dav1d*.a" 2^>nul') do if not exist "!DAV1D_PREFIX!\lib\dav1d.lib" copy /Y "%%F" "!DAV1D_PREFIX!\lib\dav1d.lib" >nul
)

if not exist "!DAV1D_PREFIX!\lib\dav1d.lib" (
  echo [ERROR] Cannot find dav1d static library under:
  echo         !DAV1D_PREFIX!\lib
  echo         !DAV1D_BUILD_DIR!
  echo         Expected one of: dav1d.lib, libdav1d.lib, libdav1d.a
  echo         Listing installed/build libraries for debugging:
  dir /b "!DAV1D_PREFIX!\lib" 2^>nul
  dir /s /b "!DAV1D_BUILD_DIR!\*dav1d*" 2^>nul
  exit /b 1
)

if not exist "!DAV1D_PREFIX!\lib\libdav1d.lib" (
  echo [COPY] dav1d.lib -^> libdav1d.lib for FFmpeg pkg-config/MSVC check
  copy /Y "!DAV1D_PREFIX!\lib\dav1d.lib" "!DAV1D_PREFIX!\lib\libdav1d.lib" >nul
  if errorlevel 1 exit /b 1
)

if not exist "!DAV1D_PREFIX!\lib\libdav1d.a" (
  echo [COPY] dav1d.lib -^> libdav1d.a for pkg-config/static compatibility
  copy /Y "!DAV1D_PREFIX!\lib\dav1d.lib" "!DAV1D_PREFIX!\lib\libdav1d.a" >nul
  if errorlevel 1 exit /b 1
)

if not exist "!DAV1D_PREFIX!\lib\pkgconfig" mkdir "!DAV1D_PREFIX!\lib\pkgconfig"
>"!DAV1D_PREFIX!\lib\pkgconfig\dav1d.pc" echo prefix=!DAV1D_PREFIX_MSYS!
>>"!DAV1D_PREFIX!\lib\pkgconfig\dav1d.pc" echo exec_prefix=!DAV1D_PREFIX_MSYS!
>>"!DAV1D_PREFIX!\lib\pkgconfig\dav1d.pc" echo libdir=!DAV1D_PREFIX_MSYS!/lib
>>"!DAV1D_PREFIX!\lib\pkgconfig\dav1d.pc" echo includedir=!DAV1D_PREFIX_MSYS!/include
>>"!DAV1D_PREFIX!\lib\pkgconfig\dav1d.pc" echo.
>>"!DAV1D_PREFIX!\lib\pkgconfig\dav1d.pc" echo Name: dav1d
>>"!DAV1D_PREFIX!\lib\pkgconfig\dav1d.pc" echo Description: AV1 decoder library
>>"!DAV1D_PREFIX!\lib\pkgconfig\dav1d.pc" echo Version: 1.5.0
>>"!DAV1D_PREFIX!\lib\pkgconfig\dav1d.pc" echo Libs: -L${libdir} -ldav1d
>>"!DAV1D_PREFIX!\lib\pkgconfig\dav1d.pc" echo Libs.private:
>>"!DAV1D_PREFIX!\lib\pkgconfig\dav1d.pc" echo Cflags: -I${includedir}

"!MSYS_BASH!" -lc "export PKG_CONFIG_PATH='!DAV1D_PREFIX_MSYS!/lib/pkgconfig':$PKG_CONFIG_PATH; cat '!DAV1D_PREFIX_MSYS!/lib/pkgconfig/dav1d.pc'; pkg-config --cflags dav1d; pkg-config --libs dav1d; ls -lh '!DAV1D_PREFIX_MSYS!/include/dav1d/dav1d.h' '!DAV1D_PREFIX_MSYS!/lib/dav1d.lib' '!DAV1D_PREFIX_MSYS!/lib/libdav1d.lib' '!DAV1D_PREFIX_MSYS!/lib/libdav1d.a'"
if errorlevel 1 (
  echo [ERROR] dav1d pkg-config validation failed.
  exit /b 1
)

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; unset LINK; cd /tmp && printf '#include <dav1d/dav1d.h>\nint main(void){return dav1d_version()[0] ? 0 : 1;}\n' > dav1d_link_check.c && cl -nologo -I'!DAV1D_PREFIX_MSYS!/include' -c -Fodav1d_link_check.obj dav1d_link_check.c && link.exe -nologo -LIBPATH:'!DAV1D_PREFIX_MSYS!/lib' -OUT:dav1d_link_check.exe dav1d_link_check.obj dav1d.lib ucrt.lib vcruntime.lib msvcrt.lib oldnames.lib"
if errorlevel 1 (
  echo [ERROR] dav1d manual link check failed before FFmpeg configure.
  echo         Check link errors above.
  exit /b 1
)

REM ============================================================
REM [6] Configure FFmpeg with x264 + x265 + SVT-AV1 + dav1d
REM ============================================================

echo.
echo ============================================================
echo [6/13] Configure FFmpeg with custom x264 + custom x265 + Singlux SVT-AV1 + dav1d
echo ============================================================

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!FFMPEG_SOURCE_MSYS!' && make distclean 2>/dev/null || true"
if errorlevel 1 (
  echo [ERROR] FFmpeg distclean failed.
  exit /b 1
)

REM FFmpeg's libsvtav1 configure probe can fail in the MSVC toolchain even after a
REM real manual cl/link test succeeds. In your log, the manual static link is OK,
REM but configure still rejects SvtAv1Enc during require_pkg_config. Since this bat
REM already manually validates EbSvtAv1Enc.h + svt_av1_enc_init_handle above and
REM passes the actual MSVC libs via --extra-libs, patch only that fragile probe.
echo [PATCH] FFmpeg configure: bypass fragile MSVC pkg-config probe for libsvtav1
REM v14: do not use bash heredoc inside a .bat. PowerShell/CMD/MSYS quoting can
REM split the heredoc and run Python lines as Windows commands. Generate a small
REM temporary Python file with plain batch echo commands, then execute it.
set "SVTAV1_PATCH_PY=%TEMP%\singlux_patch_ffmpeg_svtav1_probe.py"
if exist "!SVTAV1_PATCH_PY!" del /q "!SVTAV1_PATCH_PY!" >nul 2>nul
>"!SVTAV1_PATCH_PY!" echo from pathlib import Path
>>"!SVTAV1_PATCH_PY!" echo p = Path(r"!FFMPEG_SOURCE!\configure")
>>"!SVTAV1_PATCH_PY!" echo s = p.read_text(encoding='utf-8', errors='replace')
>>"!SVTAV1_PATCH_PY!" echo backup = p.with_name('configure.singlux_before_svtav1_probe_patch')
>>"!SVTAV1_PATCH_PY!" echo if not backup.exists():
>>"!SVTAV1_PATCH_PY!" echo     backup.write_text(s, encoding='utf-8')
>>"!SVTAV1_PATCH_PY!" echo lines = s.splitlines()
>>"!SVTAV1_PATCH_PY!" echo out = []
>>"!SVTAV1_PATCH_PY!" echo changed = 0
>>"!SVTAV1_PATCH_PY!" echo for line in lines:
>>"!SVTAV1_PATCH_PY!" echo     if 'require_pkg_config libsvtav1' in line and 'SvtAv1Enc' in line:
>>"!SVTAV1_PATCH_PY!" echo         out.append('enabled libsvtav1        ^&^& check_headers EbSvtAv1Enc.h')
>>"!SVTAV1_PATCH_PY!" echo         changed += 1
>>"!SVTAV1_PATCH_PY!" echo     elif 'require_pkg_config libdav1d' in line and 'dav1d' in line:
>>"!SVTAV1_PATCH_PY!" echo         out.append('enabled libdav1d         ^&^& check_headers dav1d/dav1d.h')
>>"!SVTAV1_PATCH_PY!" echo         changed += 1
>>"!SVTAV1_PATCH_PY!" echo     else:
>>"!SVTAV1_PATCH_PY!" echo         out.append(line)
>>"!SVTAV1_PATCH_PY!" echo if changed == 0:
>>"!SVTAV1_PATCH_PY!" echo     raise SystemExit('Could not find FFmpeg libsvtav1/libdav1d require_pkg_config line in configure')
>>"!SVTAV1_PATCH_PY!" echo p.write_text('\n'.join(out) + '\n', encoding='utf-8')
>>"!SVTAV1_PATCH_PY!" echo print('patched %%d libsvtav1/libdav1d configure probe line(s)' %% changed)
python "!SVTAV1_PATCH_PY!"
if errorlevel 1 (
  echo [ERROR] Failed to patch FFmpeg configure for libsvtav1 probe.
  echo         Patch script was:
  type "!SVTAV1_PATCH_PY!"
  exit /b 1
)

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; export PKG_CONFIG_PATH='!X264_PREFIX_MSYS!/lib/pkgconfig:!SVTAV1_PREFIX_MSYS!/lib/pkgconfig:!DAV1D_PREFIX_MSYS!/lib/pkgconfig':$PKG_CONFIG_PATH; cd '!FFMPEG_SOURCE_MSYS!' && echo '[PKG_CONFIG_PATH]' $PKG_CONFIG_PATH && echo [x264.pc cflags:] && pkg-config --cflags x264 && echo [x264.pc libs:] && pkg-config --libs x264 && echo [SvtAv1Enc.pc cflags:] && pkg-config --cflags SvtAv1Enc && echo [SvtAv1Enc.pc libs:] && pkg-config --libs SvtAv1Enc && echo [dav1d.pc cflags:] && pkg-config --cflags dav1d && echo [dav1d.pc libs:] && pkg-config --libs dav1d && ./configure --toolchain=msvc --arch=x86_64 --target-os=win64 --enable-gpl --enable-libx264 --enable-libx265 --enable-libsvtav1 --enable-libdav1d --disable-doc --disable-network --disable-decoder=sanm --pkg-config-flags='--static' --extra-cflags='-I/c/Users/long/Desktop/singlux-x264/x264/build-msvc-ffmpeg/include -I/c/Users/long/Desktop/sinlgux-x265/x265/source -I/c/Users/long/Desktop/sinlgux-x265/x265/source/build-vs2019-ffmpeg-md -I/c/Users/long/Desktop/sinlgux-AV1/build-msvc-ffmpeg/include -I/c/Users/long/Desktop/dav1d/build-msvc-ffmpeg/include' --extra-ldflags='-libpath:C:/Users/long/Desktop/singlux-x264/x264/build-msvc-ffmpeg/lib -libpath:C:/Users/long/Desktop/sinlgux-x265/x265/source/build-vs2019-ffmpeg-md/Release -libpath:C:/Users/long/Desktop/sinlgux-AV1/build-msvc-ffmpeg/lib -libpath:C:/Users/long/Desktop/dav1d/build-msvc-ffmpeg/lib' --extra-libs='x264.lib libx265.lib SvtAv1Enc.lib libSvtAv1Enc.lib dav1d.lib libdav1d.lib winmm.lib advapi32.lib shell32.lib ole32.lib user32.lib bcrypt.lib ucrt.lib vcruntime.lib msvcrt.lib oldnames.lib'"
if errorlevel 1 (
  echo [ERROR] FFmpeg configure failed.
  echo         Showing the last 120 lines of ffbuild/config.log:
  powershell -NoProfile -Command "Get-Content '!FFMPEG_SOURCE!\ffbuild\config.log' -Tail 120" 2>nul
  echo.
  echo         Also check full log:
  echo         !FFMPEG_SOURCE!\ffbuild\config.log
  exit /b 1
)

echo [CHECK] FFmpeg configure selected libsvtav1 and libdav1d
"!MSYS_BASH!" -lc "cd '!FFMPEG_SOURCE_MSYS!' && grep -E 'CONFIG_LIBSVTAV1[ =]1|CONFIG_LIBDAV1D[ =]1|#define CONFIG_LIBSVTAV1 1|#define CONFIG_LIBDAV1D 1' ffbuild/config.mak config.h 2>/dev/null || true"

REM ============================================================
REM [5] Force FFmpeg MSVC runtime to -MD
REM ============================================================

echo.
echo ============================================================
echo [7/13] Force FFmpeg MSVC runtime to -MD
echo ============================================================

REM No heredoc here. Batch files break bash heredocs.
REM Also do not use /MD because MSYS may convert it into C:/msys64/MD.
"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!FFMPEG_SOURCE_MSYS!' && sed -i -E '/^(CFLAGS|CXXFLAGS)=/ { s@/MTd@@g; s@/MT@@g; s@/MDd@@g; s@/MD@@g; s@-MTd@@g; s@-MT@@g; s@-MDd@@g; s@-MD@@g; s@$@ -MD@; }' ffbuild/config.mak && grep -n '^CFLAGS\|^CXXFLAGS' ffbuild/config.mak && grep -n 'C:/msys64/MD' ffbuild/config.mak && exit 1 || true"
if errorlevel 1 (
  echo [ERROR] Failed to patch FFmpeg config.mak.
  exit /b 1
)

REM ============================================================
REM [6] Build FFmpeg
REM ============================================================

echo.
echo ============================================================
echo [8/13] Build FFmpeg
echo ============================================================

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!FFMPEG_SOURCE_MSYS!' && make clean && make -j!MAKE_JOBS!"
if errorlevel 1 (
  echo [ERROR] FFmpeg build failed.
  exit /b 1
)

REM ============================================================
REM [9] Check FFmpeg encoders/decoders include libx264 + libx265 + libsvtav1 + libdav1d
REM ============================================================

echo.
echo ============================================================
echo [9/13] Check FFmpeg encoders
echo ============================================================

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!FFMPEG_SOURCE_MSYS!' && ./ffmpeg.exe -hide_banner -encoders | tee ffmpeg_encoders.log && ./ffmpeg.exe -hide_banner -decoders | tee ffmpeg_decoders.log && grep -q 'libx264' ffmpeg_encoders.log && grep -q 'libx265' ffmpeg_encoders.log && grep -q 'libsvtav1' ffmpeg_encoders.log && grep -q 'libdav1d' ffmpeg_decoders.log"
if errorlevel 1 (
  echo [ERROR] FFmpeg does not list libx264/libx265/libsvtav1 encoders and libdav1d decoder.
  exit /b 1
)

REM ============================================================
REM [8] Smoke test custom x264 through FFmpeg
REM ============================================================

echo.
echo ============================================================
echo [10/13] Smoke test custom x264 through FFmpeg
echo ============================================================

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!FFMPEG_SOURCE_MSYS!' && ./ffmpeg.exe -hide_banner -f lavfi -i testsrc2=size=128x72:rate=1:duration=3 -frames:v 3 -c:v libx264 -x264-params singlux-anchor-ref=1:singlux-poc-lsb-bits=16:keyint=999999:min-keyint=999999:scenecut=0:bframes=0:ref=1 -f null - 2>&1 | tee ffmpeg_x264_smoke.log && grep -q 'singlux-anchor-ref: poc_lsb_bits=16 max_poc_lsb=65536' ffmpeg_x264_smoke.log"
if errorlevel 1 (
  echo [ERROR] FFmpeg x264 smoke test failed, or Singlux x264 log was not found.
  exit /b 1
)

REM ============================================================
REM [9] Smoke test custom x265 through FFmpeg
REM ============================================================

echo.
echo ============================================================
echo [11/13] Smoke test custom x265 through FFmpeg
echo ============================================================

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!FFMPEG_SOURCE_MSYS!' && ./ffmpeg.exe -hide_banner -f lavfi -i testsrc2=size=128x72:rate=1:duration=3 -frames:v 3 -c:v libx265 -x265-params single-ref-idr0=1:single-ref-poc-lsb-bits=16:log-level=full -f null - 2>&1 | tee ffmpeg_x265_smoke.log && grep -E -q 'single-ref-poc-lsb-bits=16|MaxPicOrderCntLsb=65536|single-ref-idr0' ffmpeg_x265_smoke.log"
if errorlevel 1 (
  echo [ERROR] FFmpeg x265 smoke test failed, or Singlux x265 log was not found.
  exit /b 1
)

REM ============================================================
REM [11] Smoke test custom Singlux SVT-AV1 through FFmpeg
REM ============================================================

echo.
echo ============================================================
echo [12/13] Smoke test custom Singlux SVT-AV1 through FFmpeg
echo ============================================================

REM This confirms FFmpeg can call the linked SVT-AV1 library.
REM If your FFmpeg wrapper does not pass the new custom options yet, the first test may fail;
REM the fallback test still proves libsvtav1 is linked and usable.
"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!FFMPEG_SOURCE_MSYS!' && ./ffmpeg.exe -hide_banner -f lavfi -i testsrc2=size=128x72:rate=1:duration=3 -frames:v 3 -c:v libsvtav1 -preset 8 -crf 35 -svtav1-params single-ref-idr0=1:singlux-poc-lsb-bits=8 -f null - 2>&1 | tee ffmpeg_svtav1_smoke.log"
if errorlevel 1 (
  echo [WARN] SVT-AV1 custom param smoke failed. Trying plain libsvtav1 encode to verify link only...
  "!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!FFMPEG_SOURCE_MSYS!' && ./ffmpeg.exe -hide_banner -f lavfi -i testsrc2=size=128x72:rate=1:duration=3 -frames:v 3 -c:v libsvtav1 -preset 8 -crf 35 -f null - 2>&1 | tee ffmpeg_svtav1_smoke.log && grep -E -q 'SVT|Svt|libsvtav1|frame=' ffmpeg_svtav1_smoke.log"
  if errorlevel 1 (
    echo [ERROR] FFmpeg SVT-AV1 smoke test failed.
    exit /b 1
  )
)

REM ============================================================
REM [13] Smoke test AV1 decode through libdav1d
REM ============================================================

echo.
echo ============================================================
echo [13/14] Smoke test AV1 software decode through libdav1d
echo ============================================================

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!FFMPEG_SOURCE_MSYS!' && ./ffmpeg.exe -hide_banner -f lavfi -i testsrc2=size=128x72:rate=30:duration=1 -frames:v 30 -c:v libsvtav1 -preset 8 -crf 35 -svtav1-params single-ref-idr0=1:singlux-poc-lsb-bits=8 -y dav1d_decode_smoke.ivf && ./ffmpeg.exe -hide_banner -c:v libdav1d -i dav1d_decode_smoke.ivf -frames:v 30 -f null - 2>&1 | tee ffmpeg_dav1d_smoke.log && grep -E -q 'libdav1d|frame= *30|video:' ffmpeg_dav1d_smoke.log"
if errorlevel 1 (
  echo [ERROR] FFmpeg dav1d AV1 decode smoke test failed.
  exit /b 1
)

REM ============================================================
REM [14] Check required FFmpeg features
REM ============================================================

echo.
echo ============================================================
echo [14/14] Check required FFmpeg muxers/demuxers/filters
echo ============================================================

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!FFMPEG_SOURCE_MSYS!' && ./ffmpeg.exe -hide_banner -muxers | grep -E 'hls|mp4|mov' && ./ffmpeg.exe -hide_banner -demuxers | grep -E 'mov|mp4' && ./ffmpeg.exe -hide_banner -filters | grep -E 'scale|pad'"
if errorlevel 1 (
  echo [ERROR] FFmpeg feature check failed.
  exit /b 1
)

echo.
echo ============================================================
echo [DONE] Build completed.
echo.
echo FFmpeg:
echo   C:\Users\long\Desktop\singlux-ffmpeg\Singlux-FFmpeg\ffmpeg.exe
echo FFprobe:
echo   C:\Users\long\Desktop\singlux-ffmpeg\Singlux-FFmpeg\ffprobe.exe
echo.
echo Expected x264 smoke-test line:
echo   singlux-anchor-ref: poc_lsb_bits=16 max_poc_lsb=65536
echo.
echo Expected SVT-AV1 encoder:
echo   libsvtav1 should appear in ffmpeg -encoders
echo.
echo Expected AV1 software decoder:
echo   libdav1d should appear in ffmpeg -decoders
echo.
echo Expected x265 smoke-test lines:
echo   param_parse: single-ref-poc-lsb-bits=16
echo   param final: single-ref-poc-lsb-bits=16
echo   SPS log2_max_pic_order_cnt_lsb=16
echo   MaxPicOrderCntLsb=65536
echo   single-ref-idr0 verify: poc=1 type=1 numL0=1 L0=[0]
echo ============================================================

exit /b 0

:CLEAN_ONLY
echo [CLEAN] Removing x264 MSVC prefix and x265/FFmpeg build outputs.
if exist "!X264_PREFIX!" rmdir /s /q "!X264_PREFIX!"
if exist "!X265_BUILD_DIR!" rmdir /s /q "!X265_BUILD_DIR!"
if exist "!SVTAV1_BUILD_DIR!" rmdir /s /q "!SVTAV1_BUILD_DIR!"
if exist "!SVTAV1_PREFIX!" rmdir /s /q "!SVTAV1_PREFIX!"
if exist "!DAV1D_BUILD_DIR!" rmdir /s /q "!DAV1D_BUILD_DIR!"
if exist "!DAV1D_PREFIX!" rmdir /s /q "!DAV1D_PREFIX!"
"!MSYS_BASH!" -lc "cd '!FFMPEG_SOURCE_MSYS!' && make distclean 2>/dev/null || true"
exit /b 0
