#!/bin/bash

set -eux

mkdir -p {archive,download}

if [ ! -v CORE_COUNT ]; then
  CORE_COUNT=`nproc`
fi

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
  FILE="../download/${1##*/}"
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
  ../configure ${FFMPEG_ARGS} \
    --enable-opengl

  make -j${CORE_COUNT}

  zip -9 ../../../archive/ffmpeg-${FFMPEG_VERSION}-`date +%Y%m%d`.zip ffmpeg.exe ffprobe.exe ffplay.exe

  popd
}

mkcd build

build_sdl2
build_ffmpeg
