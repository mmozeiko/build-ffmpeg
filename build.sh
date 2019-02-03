#!/bin/bash

set -eux

mkdir -p {archive,download}

if [ ! -v CORE_COUNT ]; then
  CORE_COUNT=`nproc`
fi

ZLIB_VERSION=1.2.11
BZIP2_VERSION=1.0.6
XZ_VERSION=5.2.4

MFX_VERSION=1.25
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

function build_zlib()
{
  get https://www.zlib.net/zlib-${ZLIB_VERSION}.tar.xz
  pushd zlib-${ZLIB_VERSION}

  CC=x86_64-w64-mingw32-gcc        \
  CXX=x86_64-w64-mingw32-g++       \
  AR=x86_64-w64-mingw32-ar         \
  RANLIB=x86_64-w64-mingw32-ranlib \
  \
  ./configure --prefix=${MINGW} --static

  make -j${CORE_COUNT} libz.a
  install -m644 zlib.h ${MINGW}/include
  install -m644 zconf.h ${MINGW}/include
  install -m644 libz.a ${MINGW}/lib
  install -m644 zlib.pc ${MINGW}/lib/pkgconfig

  popd
}

function build_bzip2()
{
  get https://sourceforge.net/projects/bzip2/files/bzip2-${BZIP2_VERSION}.tar.gz
  pushd bzip2-${BZIP2_VERSION}

  CC=x86_64-w64-mingw32-gcc           \
  AR=x86_64-w64-mingw32-ar            \
  RANLIB=x86_64-w64-mingw32-ranlib    \
  CFLAGS="-O2 -D_FILE_OFFSET_BITS=64" \
  \
  make -j${CORE_COUNT} libbz2.a

  install -m644 libbz2.a ${MINGW}/lib
  install -m644 bzlib.h ${MINGW}/include

  popd
}

function build_xz()
{
  get https://tukaani.org/xz/xz-${XZ_VERSION}.tar.xz
  pushd xz-${XZ_VERSION}

  ./configure ${CONFIGURE_ARGS} \
    --enable-threads=vista      \
    --disable-xz                \
    --disable-xzdec             \
    --disable-lzmadec           \
    --disable-lzmainfo          \
    --disable-lzma-links        \
    --disable-scripts           \
    --disable-doc               \
    --disable-nls               \

  make -j${CORE_COUNT}
  make install

  popd
}

function build_mfx()
{
  get https://github.com/lu-zero/mfx_dispatch/archive/${MFX_VERSION}.tar.gz mfx-${MFX_VERSION}.tar.gz
  pushd mfx_dispatch-${MFX_VERSION}

  cmake ${CMAKE_ARGS} -DINTELMEDIASDK_PATH=`pwd` .
  cmake --build . -- -j${CORE_COUNT}
  cmake --build . --target install

  popd
}

function build_opencl()
{
  get https://github.com/KhronosGroup/OpenCL-ICD-Loader/archive/${OPENCL_LOADER_VERSION}.tar.gz opencl-loader.tar.gz
  get https://github.com/KhronosGroup/OpenCL-Headers/archive/${OPENCL_HEADERS_VERSION}.tar.gz opencl-headers.tar.gz

  ln -sf `pwd`/OpenCL-Headers-${OPENCL_HEADERS_VERSION}/CL ${MINGW}/include

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

  CFLAGS="-I${MINGW}/include -DAL_LIBTYPE_STATIC -DBZ_IMPORT" \
  LDFLAGS="-L${MINGW}/lib -Wl,--start-group -lole32 -lcfgmgr32" \
  \
  ../configure ${FFMPEG_ARGS} \
    --enable-opengl \
    --enable-openal \
    --enable-opencl \
    --enable-libmfx \

  make -j${CORE_COUNT}

  zip -9 ../../../archive/ffmpeg-${FFMPEG_VERSION}-`date +%Y%m%d`.zip ffmpeg.exe ffprobe.exe ffplay.exe

  popd
}

mkcd build

build_zlib
build_bzip2
build_xz
build_mfx
build_opencl
build_openal
build_sdl2
build_ffmpeg
