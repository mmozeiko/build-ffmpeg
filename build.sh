#!/bin/bash

set -eux

mkdir -p {archive,download}

if [ ! -v CORE_COUNT ]; then
  CORE_COUNT=`nproc`
fi

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

function build_ffmpeg()
{
  FFMPEG_VERSION=$1

  get https://www.ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz
  pushd ffmpeg-${FFMPEG_VERSION}

  mkcd build
  ../configure ${FFMPEG_ARGS}
  make -j${CORE_COUNT}

  zip -9 ../../../archive/ffmpeg-${FFMPEG_VERSION}-`date +%Y%m%d`.zip ffmpeg.exe ffprobe.exe

  popd
}

mkcd build

build_ffmpeg "${FFMPEG_VERSION}"
