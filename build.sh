#!/bin/bash

set -eux

mkdir -p {archive,download}

if [ ! -v CORE_COUNT ]; then
  CORE_COUNT=`nproc`
fi

OPENCL_LOADER_VERSION=master
OPENCL_HEADERS_VERSION=master
OPENAL_VERSION=1.19.1
SDL2_VERSION=2.0.9

FFMPEG_VERSION=4.1

FFMPEG_ARGS="                        \
  --arch=x86                         \
  --target-os=mingw32                \
  --cross-prefix=x86_64-w64-mingw32- \
                                     \
  --pkg-config=pkg-config            \
  --pkg-config-flags=--static        \
  --disable-debug                    \
  --disable-doc                      \
  --enable-gpl                       \
  --enable-version3                  \
  --enable-nonfree                   \
"

CONFIGURE_ARGS="            \
  --prefix=${MINGW}         \
  --host=x86_64-w64-mingw32 \
  --disable-shared          \
  --enable-static           \
"

CMAKE_ARGS="                                     \
  -DCMAKE_BUILD_TYPE=Release                     \
  -DCMAKE_SYSTEM_NAME=Windows                    \
  -DCMAKE_INSTALL_PREFIX=${MINGW}                \
  -DCMAKE_FIND_ROOT_PATH=${MINGW}                \
  -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER      \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY       \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY       \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc      \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++    \
  -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres \
  -DBUILD_SHARED_LIBS=OFF                        \
"

function get()
{
  if [ "$#" -eq 2 ]; then
    FILE="../download/$2"
  else
    FILE="../download/${1##*/}"
  fi
  if [ ! -f "${FILE}" ]; then
    wget -q "$1" -O "${FILE}"
  fi
   
  case "${1##*.}" in
  gz|tgz)
    tar --warning=none -xzf "${FILE}"
    ;;
  bz2)
    tar --warning=none -xjf "${FILE}"
    ;;
  xz)
    tar --warning=none -xJf "${FILE}"
    ;;
  *)
    echo unknown archive extension "${1##*.}"
    exit 1
    ;;
  esac
}

function mkcd()
{
  mkdir -p "$1" && cd "$1"
}

function build_opencl()
{
  get https://github.com/KhronosGroup/OpenCL-ICD-Loader/archive/${OPENCL_LOADER_VERSION}.tar.gz opencl-loader.tar.gz
  get https://github.com/KhronosGroup/OpenCL-Headers/archive/${OPENCL_HEADERS_VERSION}.tar.gz opencl-headers.tar.gz

  ln -s `pwd`/OpenCL-Headers-${OPENCL_HEADERS_VERSION}/CL ${MINGW}/include

  pushd OpenCL-ICD-Loader-${OPENCL_LOADER_VERSION}

  patch -p0 -i ../../patch/opencl-fix-mingw-build.patch
  x86_64-w64-mingw32-gcc -O2 -c -I${MINGW}/include icd.c icd_dispatch.c icd_windows.c icd_windows_hkr.c
  x86_64-w64-mingw32-ar r ${MINGW}/lib/libOpenCL.a icd.o icd_dispatch.o icd_windows.o icd_windows_hkr.o
  x86_64-w64-mingw32-ranlib ${MINGW}/lib/libOpenCL.a

  popd
}

function build_openal()
{
  get https://openal-soft.org/openal-releases/openal-soft-${OPENAL_VERSION}.tar.bz2
  pushd openal-soft-${OPENAL_VERSION}

  cmake ${CMAKE_ARGS}            \
    -DLIBTYPE="STATIC"           \
    -DALSOFT_UTILS=OFF           \
    -DALSOFT_TESTS=OFF           \
    -DALSOFT_CONFIG=OFF          \
    -DALSOFT_EXAMPLES=OFF        \
    -DALSOFT_HRTF_DEFS=OFF       \
    -DALSOFT_EMBED_HRTF_DATA=OFF \
    -DALSOFT_AMBDEC_PRESETS=OFF  \
    -DALSOFT_BACKEND_WINMM=OFF   \
    -DALSOFT_BACKEND_DSOUND=OFF  \
    -DALSOFT_BACKEND_WAVE=OFF    \
    .

  patch -p0 -i ../../patch/openal-fix-static-build.patch
  cmake --build . -- -j${CORE_COUNT}
  cmake --build . --target install

  popd
}

function build_sdl2()
{
  get https://www.libsdl.org/release/SDL2-${SDL2_VERSION}.tar.gz
  pushd SDL2-${SDL2_VERSION}

  ./configure ${CONFIGURE_ARGS} \
    --disable-joystick          \
    --disable-haptic            \
    --disable-sensor            \
    --disable-power             \
    --disable-filesystem        \
    --disable-file              \
    --disable-diskaudio         \
    --disable-dummyaudio        \
    --disable-video-dummy       \
    --disable-video-opengles    \
    --disable-video-vulkan      \
    CFLAGS="-DDECLSPEC="

  patch -p0 -i ../../patch/sdl2-no-dynapi.patch
  make -j${CORE_COUNT}
  make install

  popd
}

function build_ffmpeg()
{
  get https://www.ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz
  pushd ffmpeg-${FFMPEG_VERSION}

  mkcd build

  CFLAGS="-I${MINGW}/include -DAL_LIBTYPE_STATIC" \
  LDFLAGS="-L${MINGW}/lib -Wl,--start-group -lole32 -lcfgmgr32" \
  \
  ../configure ${FFMPEG_ARGS} \
    --enable-opengl \
    --enable-openal \
    --enable-opencl

  make -j${CORE_COUNT}

  zip -9 ../../../archive/ffmpeg-${FFMPEG_VERSION}-`date +%Y%m%d`.zip ffmpeg.exe ffprobe.exe ffplay.exe

  popd
}

mkcd build

build_opencl
build_openal
build_sdl2
build_ffmpeg
