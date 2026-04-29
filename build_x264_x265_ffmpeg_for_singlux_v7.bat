@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM Singlux one-shot build:
REM   1) Build custom x264 as MSVC static lib for FFmpeg
REM   2) Build custom x265 with VS2019 static lib
REM   3) Build FFmpeg --toolchain=msvc with both libx264 + libx265
REM   4) Smoke test both Singlux x264 and Singlux x265 params through FFmpeg
REM
REM Run from Windows CMD, not PowerShell/MSYS:
REM   cd /d C:\Users\long\Desktop\singlux-ffmpeg\Singlux-FFmpeg
REM   build_x264_x265_ffmpeg_for_singlux_v7.bat
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
echo [0/10] Check build environment
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
echo [CHECK] MSYS sees cl/link/lib
"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; which cl; which link; which lib; cl 2>&1 | head -n 2"
if errorlevel 1 (
  echo [ERROR] MSYS cannot see cl/link/lib.
  exit /b 1
)

REM ============================================================
REM [1] Validate source patches
REM ============================================================

echo.
echo ============================================================
echo [1/10] Validate Singlux source patches
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

REM ============================================================
REM [2] Build x264 MSVC static library
REM ============================================================

echo.
echo ============================================================
echo [2/10] Build x264 MSVC static library
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
echo [3/10] Rebuild x265 with VS2019 Release
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
REM [4] Configure FFmpeg with x264 + x265
REM ============================================================

echo.
echo ============================================================
echo [4/10] Configure FFmpeg with custom x264 + custom x265
echo ============================================================

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!FFMPEG_SOURCE_MSYS!' && make distclean 2>/dev/null || true"
if errorlevel 1 (
  echo [ERROR] FFmpeg distclean failed.
  exit /b 1
)

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; export PKG_CONFIG_PATH='!X264_PREFIX_MSYS!/lib/pkgconfig':$PKG_CONFIG_PATH; cd '!FFMPEG_SOURCE_MSYS!' && echo '[PKG_CONFIG_PATH]' $PKG_CONFIG_PATH && echo [x264.pc cflags:] && pkg-config --cflags x264 && echo [x264.pc libs:] && pkg-config --libs x264 && ./configure --toolchain=msvc --arch=x86_64 --target-os=win64 --enable-gpl --enable-libx264 --enable-libx265 --disable-doc --disable-network --disable-decoder=sanm --pkg-config-flags='--static' --extra-cflags='-I/c/Users/long/Desktop/singlux-x264/x264/build-msvc-ffmpeg/include -I/c/Users/long/Desktop/sinlgux-x265/x265/source -I/c/Users/long/Desktop/sinlgux-x265/x265/source/build-vs2019-ffmpeg-md' --extra-ldflags='-libpath:C:/Users/long/Desktop/singlux-x264/x264/build-msvc-ffmpeg/lib -libpath:C:/Users/long/Desktop/sinlgux-x265/x265/source/build-vs2019-ffmpeg-md/Release' --extra-libs='x264.lib libx265.lib ucrt.lib vcruntime.lib msvcrt.lib oldnames.lib'"
if errorlevel 1 (
  echo [ERROR] FFmpeg configure failed.
  echo         Showing the last 120 lines of ffbuild/config.log:
  powershell -NoProfile -Command "Get-Content '!FFMPEG_SOURCE!\ffbuild\config.log' -Tail 120" 2>nul
  echo.
  echo         Also check full log:
  echo         !FFMPEG_SOURCE!\ffbuild\config.log
  exit /b 1
)

REM ============================================================
REM [5] Force FFmpeg MSVC runtime to -MD
REM ============================================================

echo.
echo ============================================================
echo [5/10] Force FFmpeg MSVC runtime to -MD
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
echo [6/10] Build FFmpeg
echo ============================================================

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!FFMPEG_SOURCE_MSYS!' && make clean && make -j!MAKE_JOBS!"
if errorlevel 1 (
  echo [ERROR] FFmpeg build failed.
  exit /b 1
)

REM ============================================================
REM [7] Check FFmpeg encoders include libx264 + libx265
REM ============================================================

echo.
echo ============================================================
echo [7/10] Check FFmpeg encoders
echo ============================================================

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!FFMPEG_SOURCE_MSYS!' && ./ffmpeg.exe -hide_banner -encoders | tee ffmpeg_encoders.log && grep -q 'libx264' ffmpeg_encoders.log && grep -q 'libx265' ffmpeg_encoders.log"
if errorlevel 1 (
  echo [ERROR] FFmpeg does not list both libx264 and libx265 encoders.
  exit /b 1
)

REM ============================================================
REM [8] Smoke test custom x264 through FFmpeg
REM ============================================================

echo.
echo ============================================================
echo [8/10] Smoke test custom x264 through FFmpeg
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
echo [9/10] Smoke test custom x265 through FFmpeg
echo ============================================================

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd '!FFMPEG_SOURCE_MSYS!' && ./ffmpeg.exe -hide_banner -f lavfi -i testsrc2=size=128x72:rate=1:duration=3 -frames:v 3 -c:v libx265 -x265-params single-ref-idr0=1:single-ref-poc-lsb-bits=16:log-level=full -f null - 2>&1 | tee ffmpeg_x265_smoke.log && grep -E -q 'single-ref-poc-lsb-bits=16|MaxPicOrderCntLsb=65536|single-ref-idr0' ffmpeg_x265_smoke.log"
if errorlevel 1 (
  echo [ERROR] FFmpeg x265 smoke test failed, or Singlux x265 log was not found.
  exit /b 1
)

REM ============================================================
REM [10] Check required FFmpeg features
REM ============================================================

echo.
echo ============================================================
echo [10/10] Check required FFmpeg muxers/demuxers/filters
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
"!MSYS_BASH!" -lc "cd '!FFMPEG_SOURCE_MSYS!' && make distclean 2>/dev/null || true"
exit /b 0
