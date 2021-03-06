#!/bin/bash

set -eux

mkdir -p {archive,download}

if [ ! -v CORE_COUNT ]; then
  CORE_COUNT=`nproc`
fi

ZLIB_VERSION=1.2.11
BZIP2_VERSION=1.0.6
XZ_VERSION=5.2.4
WINICONV_VERSION=0.0.8
LIBXML2_VERSION=2.9.9
X264_VERSION=stable
X265_VERSION=3.0
FDK_AAC_VERSION=2.0.0
CHROMAPRINT_VERSION=1.4.3
MFX_VERSION=1.25
OPENCL_LOADER_VERSION=master
OPENCL_HEADERS_VERSION=master
OPENAL_VERSION=1.19.1
SDL2_VERSION=2.0.9

FFMPEG_VERSION=4.1.1

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

function build_winiconv()
{
  get https://github.com/win-iconv/win-iconv/archive/v${WINICONV_VERSION}.tar.gz winiconv-${WINICONV_VERSION}.tar.gz
  pushd win-iconv-${WINICONV_VERSION}

  CC=x86_64-w64-mingw32-gcc \
  AR=x86_64-w64-mingw32-ar \
  RANLIB=x86_64-w64-mingw32-ranlib \
  CFLAGS="-O2" \
  \
  make libiconv.a

  install -m644 libiconv.a ${MINGW}/lib
  install -m644 iconv.h ${MINGW}/include

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

function build_libxml2()
{
  get ftp://xmlsoft.org/libxml2/libxml2-${LIBXML2_VERSION}.tar.gz
  pushd libxml2-${LIBXML2_VERSION}

  ./configure ${CONFIGURE_ARGS} \
    --with-iconv="${MINGW}"     \
    --without-ftp               \
    --without-http              \
    --without-python            \
    --without-zlib              \
    --without-lzma              \

  make -j${CORE_COUNT}
  make install

  popd
}

function build_libx264()
{
  get https://github.com/mirror/x264/archive/${X264_VERSION}.tar.gz x264-${X264_VERSION}.tar.gz
  pushd x264-${X264_VERSION}

  ./configure ${CONFIGURE_ARGS}        \
    --cross-prefix=x86_64-w64-mingw32- \
    --disable-cli                      \

  patch -p0 -i ../../patch/x264-install-permissions.patch
  make -j${CORE_COUNT}
  make install

  popd
}

function build_libx265()
{
  get https://bitbucket.org/multicoreware/x265/downloads/x265_${X265_VERSION}.tar.gz
  pushd x265_${X265_VERSION}

  cmake -B build12 ${CMAKE_ARGS} -DENABLE_SHARED=OFF -DEXPORT_C_API=OFF -DENABLE_CLI=OFF -DHIGH_BIT_DEPTH=ON -DMAIN12=ON source
  cmake --build build12 -- -j${CORE_COUNT}

  cmake -B build10 ${CMAKE_ARGS} -DENABLE_SHARED=OFF -DEXPORT_C_API=OFF -DENABLE_CLI=OFF -DHIGH_BIT_DEPTH=ON source
  cmake --build build10 -- -j${CORE_COUNT}

  cmake -B build ${CMAKE_ARGS} -DENABLE_SHARED=OFF -DEXTRA_LIB="${PWD}/build12/libx265.a;${PWD}/build10/libx265.a" -DENABLE_CLI=OFF -DLINKED_10BIT=ON -DLINKED_12BIT=ON source
  cmake --build build -- -j${CORE_COUNT}

  mv build/libx265.a build/libx265_main.a
  x86_64-w64-mingw32-ar -M <<EOF
CREATE build/libx265.a
ADDLIB build/libx265_main.a
ADDLIB build10/libx265.a
ADDLIB build12/libx265.a
SAVE
END
EOF

  cmake --build build --target install

  popd
}

function build_chromparint()
{
  get https://github.com/acoustid/chromaprint/releases/download/v${CHROMAPRINT_VERSION}/chromaprint-${CHROMAPRINT_VERSION}.tar.gz
  pushd chromaprint-v${CHROMAPRINT_VERSION}

  cmake ${CMAKE_ARGS} -DFFT_LIB=avfft .
  cmake --build . -- -j${CORE_COUNT}
  cmake --build . --target install

  popd
}

function build_fdk_aac()
{
  get https://sourceforge.net/projects/opencore-amr/files/fdk-aac/fdk-aac-${FDK_AAC_VERSION}.tar.gz

  pushd fdk-aac-${FDK_AAC_VERSION}
  ./configure ${CONFIGURE_ARGS}

  make -j${CORE_COUNT}
  make install

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

function build_ffmpeg_stub()
{
  get https://www.ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz
  pushd ffmpeg-${FFMPEG_VERSION}

  mkcd build

  ../configure ${FFMPEG_ARGS} \
    --prefix=${MINGW}         \
    --disable-programs        \
    --disable-network         \
    --disable-everything      \
    --enable-rdft             \
    --disable-bzlib           \
    --disable-iconv           \
    --disable-lzma            \
    --disable-schannel        \
    --disable-sdl2            \
    --disable-zlib            \
    --disable-amf             \
    --disable-cuvid           \
    --disable-d3d11va         \
    --disable-dxva2           \
    --disable-ffnvcodec       \
    --disable-nvdec           \
    --disable-nvenc           \

  make -j${CORE_COUNT}
  make install

  popd
}

function build_ffmpeg()
{
  get https://www.ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz
  pushd ffmpeg-${FFMPEG_VERSION}

  mkcd build

  CFLAGS="-I${MINGW}/include -DAL_LIBTYPE_STATIC -DBZ_IMPORT -DCHROMAPRINT_NODLL" \
  LDFLAGS="-L${MINGW}/lib -Wl,--start-group -lbcrypt -lole32 -lcfgmgr32 -lstdc++ -lavcodec -lavutil" \
  \
  ../configure ${FFMPEG_ARGS} \
    --enable-avisynth \
    --enable-chromaprint \
    --enable-libfdk-aac \
    --enable-libxml2 \
    --enable-libx264 \
    --enable-libx265 \
    --enable-opengl \
    --enable-openal \
    --enable-opencl \
    --enable-libmfx \

  make -j${CORE_COUNT}

  zip -9 ../../../archive/ffmpeg-${FFMPEG_VERSION}-`date +%Y%m%d`.zip ffmpeg.exe ffprobe.exe ffplay.exe

  popd
}

mkcd build

build_ffmpeg_stub

build_zlib
build_bzip2
build_xz
build_winiconv
build_libx264
build_libx265
build_libxml2
build_chromparint
build_fdk_aac
build_mfx
build_opencl
build_openal
build_sdl2

build_ffmpeg
