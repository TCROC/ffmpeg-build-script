#!/bin/bash

# HOMEPAGE: https://github.com/markus-perl/ffmpeg-build-script
# LICENSE: https://github.com/markus-perl/ffmpeg-build-script/blob/master/LICENSE

PROGNAME=$(basename "$0")
FFMPEG_VERSION=5.0
SCRIPT_VERSION=1.36
CWD=$(pwd)
PACKAGES="$CWD/packages"
WORKSPACE="$CWD/workspace"
CFLAGS="-I$WORKSPACE/include"
LDFLAGS="-L$WORKSPACE/lib"
LDEXEFLAGS=""
EXTRALIBS="-ldl -lpthread -lm -lz"
MACOS_M1=false
CONFIGURE_OPTIONS=() # not used
NONFREE_AND_GPL=false
LATEST=false

# Check for Apple Silicon
if [[ ("$(uname -m)" == "arm64") && ("$OSTYPE" == "darwin"*) ]]; then
  # If arm64 AND darwin (macOS)
  export ARCH=arm64
  export MACOSX_DEPLOYMENT_TARGET=11.0
  MACOS_M1=true
fi

# Speed up the process
# Env Var NUMJOBS overrides automatic detection
if [[ -n "$NUMJOBS" ]]; then
  MJOBS="$NUMJOBS"
elif [[ -f /proc/cpuinfo ]]; then
  MJOBS=$(grep -c processor /proc/cpuinfo)
elif [[ "$OSTYPE" == "darwin"* ]]; then
  MJOBS=$(sysctl -n machdep.cpu.thread_count)
  CONFIGURE_OPTIONS=("--enable-videotoolbox")
  MACOS_LIBTOOL="$(which libtool)" # gnu libtool is installed in this script and need to avoid name conflict
else
  MJOBS=4
fi

make_dir() {
  remove_dir "$1"
  if ! mkdir "$1"; then
    printf "\n Failed to create dir %s" "$1"
    exit 1
  fi
}

remove_dir() {
  if [ -d "$1" ]; then
    rm -r "$1"
  fi
}

download() {
  # download url [filename[dirname]]

  DOWNLOAD_PATH="$PACKAGES"
  DOWNLOAD_FILE="${2:-"${1##*/}"}"

  if [[ "$DOWNLOAD_FILE" =~ tar. ]]; then
    TARGETDIR="${DOWNLOAD_FILE%.*}"
    TARGETDIR="${3:-"${TARGETDIR%.*}"}"
  else
    TARGETDIR="${3:-"${DOWNLOAD_FILE%.*}"}"
  fi

  if [ ! -f "$DOWNLOAD_PATH/$DOWNLOAD_FILE" ]; then
    echo "Downloading $1 as $DOWNLOAD_FILE"
    curl -L --silent -o "$DOWNLOAD_PATH/$DOWNLOAD_FILE" "$1"

    EXITCODE=$?
    if [ $EXITCODE -ne 0 ]; then
      echo ""
      echo "Failed to download $1. Exitcode $EXITCODE. Retrying in 10 seconds"
      sleep 10
      curl -L --silent -o "$DOWNLOAD_PATH/$DOWNLOAD_FILE" "$1"
    fi

    EXITCODE=$?
    if [ $EXITCODE -ne 0 ]; then
      echo ""
      echo "Failed to download $1. Exitcode $EXITCODE"
      exit 1
    fi

    echo "... Done"
  else
    echo "$DOWNLOAD_FILE has already downloaded."
  fi

  make_dir "$DOWNLOAD_PATH/$TARGETDIR"

  if [[ "$DOWNLOAD_FILE" == *"patch"* ]]; then
    return
  fi

  if [ -n "$3" ]; then
    if ! tar -xvf "$DOWNLOAD_PATH/$DOWNLOAD_FILE" -C "$DOWNLOAD_PATH/$TARGETDIR" 2>/dev/null >/dev/null; then
      echo "Failed to extract $DOWNLOAD_FILE"
      exit 1
    fi
  else
    if ! tar -xvf "$DOWNLOAD_PATH/$DOWNLOAD_FILE" -C "$DOWNLOAD_PATH/$TARGETDIR" --strip-components 1 2>/dev/null >/dev/null; then
      echo "Failed to extract $DOWNLOAD_FILE"
      exit 1
    fi
  fi

  echo "Extracted $DOWNLOAD_FILE"

  cd "$DOWNLOAD_PATH/$TARGETDIR" || (
    echo "Error has occurred."
    exit 1
  )
}

execute() {
  echo "$ $*"

  OUTPUT=$("$@" 2>&1)

  # shellcheck disable=SC2181
  if [ $? -ne 0 ]; then
    echo "$OUTPUT"
    echo ""
    echo "Failed to Execute $*" >&2
    exit 1
  fi
}

build() {
  echo ""
  echo "building $1 - version $2"
  echo "======================="

  if [ -f "$PACKAGES/$1.done" ]; then
    if grep -Fx "$2" "$PACKAGES/$1.done" >/dev/null; then
      echo "$1 version $2 already built. Remove $PACKAGES/$1.done lockfile to rebuild it."
      return 1
    elif $LATEST; then
      echo "$1 is outdated and will be rebuilt with latest version $2"
      return 0
    else
      echo "$1 is outdated, but will not be rebuilt. Pass in --latest to rebuild it or remove $PACKAGES/$1.done lockfile."
      return 1
    fi
  fi

  return 0
}

command_exists() {
  if ! [[ -x $(command -v "$1") ]]; then
    return 1
  fi

  return 0
}

library_exists() {
  if ! [[ -x $(pkg-config --exists --print-errors "$1" 2>&1 >/dev/null) ]]; then
    return 1
  fi

  return 0
}

build_done() {
  echo "$2" > "$PACKAGES/$1.done"
}

verify_binary_type() {
  if ! command_exists "file"; then
    return
  fi

  BINARY_TYPE=$(file "$WORKSPACE/bin/ffmpeg" | sed -n 's/^.*\:\ \(.*$\)/\1/p')
  echo ""
  case $BINARY_TYPE in
  "Mach-O 64-bit executable arm64")
    echo "Successfully built Apple Silicon (M1) for ${OSTYPE}: ${BINARY_TYPE}"
    ;;
  *)
    echo "Successfully built binary for ${OSTYPE}: ${BINARY_TYPE}"
    ;;
  esac
}

cleanup() {
  remove_dir "$PACKAGES"
  remove_dir "$WORKSPACE"
  echo "Cleanup done."
  echo ""
}

usage() {
  echo "Usage: $PROGNAME [OPTIONS]"
  echo "Options:"
  echo "  -h, --help                     Display usage information"
  echo "      --version                  Display version information"
  echo "  -b, --build                    Starts the build process"
  echo "      --enable-gpl-and-non-free  Enable GPL and non-free codecs  - https://ffmpeg.org/legal.html"
  echo "  -c, --cleanup                  Remove all working dirs"
  echo "      --latest                   Build latest version of dependencies if newer available"
  echo "      --full-static              Build a full static FFmpeg binary (eg. glibc, pthreads etc...) **only Linux**"
  echo "                                 Note: Because of the NSS (Name Service Switch), glibc does not recommend static links."
  echo ""
}

echo "ffmpeg-build-script v$SCRIPT_VERSION"
echo "========================="
echo ""

while (($# > 0)); do
  case $1 in
  -h | --help)
    usage
    exit 0
    ;;
  --version)
    echo "$SCRIPT_VERSION"
    exit 0
    ;;
  -*)
    if [[ "$1" == "--build" || "$1" =~ '-b' ]]; then
      bflag='-b'
    fi
    if [[ "$1" == "--enable-gpl-and-non-free" ]]; then
      CONFIGURE_OPTIONS+=("--enable-nonfree")
      CONFIGURE_OPTIONS+=("--enable-gpl")
      NONFREE_AND_GPL=true
    fi
    if [[ "$1" == "--cleanup" || "$1" =~ '-c' && ! "$1" =~ '--' ]]; then
      cflag='-c'
      cleanup
    fi
    if [[ "$1" == "--full-static" ]]; then
      if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Error: A full static binary can only be build on Linux."
        exit 1
      fi
      LDEXEFLAGS="-static"
    fi
    if [[ "$1" == "--latest" ]]; then
      LATEST=true
    fi
    shift
    ;;
  *)
    usage
    exit 1
    ;;
  esac
done

if [ -z "$bflag" ]; then
  if [ -z "$cflag" ]; then
    usage
    exit 1
  fi
  exit 0
fi

echo "Using $MJOBS make jobs simultaneously."

if $NONFREE_AND_GPL; then
  echo "With GPL and non-free codecs"
fi

if [ -n "$LDEXEFLAGS" ]; then
  echo "Start the build in full static mode."
fi

mkdir -p "$PACKAGES"
mkdir -p "$WORKSPACE"

export PATH="${WORKSPACE}/bin:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/share/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig:/usr/lib64/pkgconfig"
export PKG_CONFIG_PATH

if ! command_exists "make"; then
  echo "make not installed."
  exit 1
fi

if ! command_exists "g++"; then
  echo "g++ not installed."
  exit 1
fi

if ! command_exists "curl"; then
  echo "curl not installed."
  exit 1
fi

if ! command_exists "cargo"; then
  echo "cargo not installed. rav1e encoder will not be available."
fi

if ! command_exists "python3"; then
  echo "python3 command not found. Lv2 filter and dav1d decoder will not be available."
fi

##
## build tools
##

if build "giflib" "5.2.1"; then
  download "https://netcologne.dl.sourceforge.net/project/giflib/giflib-5.2.1.tar.gz"
    if [[ "$OSTYPE" == "darwin"* ]]; then
      download "https://sourceforge.net/p/giflib/bugs/_discuss/thread/4e811ad29b/c323/attachment/Makefile.patch"
      execute patch -p0 --forward "${PACKAGES}/giflib-5.2.1/Makefile" "${PACKAGES}/Makefile.patch" || true
    fi
  cd "${PACKAGES}"/giflib-5.2.1 || exit
  #multicore build disabled for this library
  execute make
  execute make PREFIX="${WORKSPACE}" install
  build_done "giflib" "5.2.1"
fi

if build "pkg-config" "0.29.2"; then
  download "https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz"
  execute ./configure --silent --prefix="${WORKSPACE}" --with-pc-path="${WORKSPACE}"/lib/pkgconfig --with-internal-glib
  execute make -j $MJOBS
  execute make install
  build_done "pkg-config" "0.29.2"
fi

if build "yasm" "1.3.0"; then
  download "https://github.com/yasm/yasm/releases/download/v1.3.0/yasm-1.3.0.tar.gz"
  execute ./configure --prefix="${WORKSPACE}"
  execute make -j $MJOBS
  execute make install
  build_done "yasm" "1.3.0"
fi

if build "zlib" "1.2.12"; then
  download "https://www.zlib.net/zlib-1.2.12.tar.gz"
  execute ./configure --static --prefix="${WORKSPACE}"
  execute make -j $MJOBS
  execute make install
  build_done "zlib" "1.2.12"
fi

if build "vaapi" "1"; then
  build_done "vaapi" "1"
fi

##
## HWaccel library
##

if [[ "$OSTYPE" == "linux-gnu" ]]; then
  if command_exists "nvcc"; then
    if build "nv-codec" "11.1.5.0"; then
      download "https://github.com/FFmpeg/nv-codec-headers/releases/download/n11.1.5.0/nv-codec-headers-11.1.5.0.tar.gz"
      execute make PREFIX="${WORKSPACE}"
      execute make install PREFIX="${WORKSPACE}"
      build_done "nv-codec" "11.1.5.0"
    fi
    CFLAGS+=" -I/usr/local/cuda/include"
    LDFLAGS+=" -L/usr/local/cuda/lib64"
    CONFIGURE_OPTIONS+=("--enable-cuvid" "--enable-nvenc")

    if $NONFREE_AND_GPL; then
      CONFIGURE_OPTIONS+=("--enable-cuda-nvcc" "--enable-cuda-llvm")

      if [ -z "$LDEXEFLAGS" ]; then
        CONFIGURE_OPTIONS+=("--enable-libnpp") # Only libnpp cannot be statically linked.
      fi
    fi

    # https://arnon.dk/matching-sm-architectures-arch-and-gencode-for-various-nvidia-cards/
    CONFIGURE_OPTIONS+=("--nvccflags=-gencode arch=compute_52,code=sm_52")
  fi

  if build "amf" "1.4.21.0"; then
    download "https://github.com/GPUOpen-LibrariesAndSDKs/AMF/archive/refs/tags/v.1.4.21.tar.gz" "AMF-1.4.21.tar.gz" "AMF-1.4.21"
    execute rm -rf "${WORKSPACE}/include/AMF"
    execute mkdir -p "${WORKSPACE}/include/AMF"
    execute cp -r "${PACKAGES}"/AMF-1.4.21/AMF-v.1.4.21/amf/public/include/* "${WORKSPACE}/include/AMF/"
    build_done "amf" "1.4.21.0"
  fi
  CONFIGURE_OPTIONS+=("--enable-amf")
fi

##
## FFmpeg
##

EXTRA_VERSION=""
if [[ "$OSTYPE" == "darwin"* ]]; then
  EXTRA_VERSION="${FFMPEG_VERSION}"
fi

build "ffmpeg" "$FFMPEG_VERSION"
download "https://github.com/FFmpeg/FFmpeg/archive/refs/heads/release/$FFMPEG_VERSION.tar.gz" "FFmpeg-release-$FFMPEG_VERSION.tar.gz"
# shellcheck disable=SC2086
./configure  \
  --disable-everything \
  --enable-videotoolbox \
  --disable-shared \
  --enable-static \
  --enable-small \
  --enable-version3 \
  --extra-cflags='-I/app/workspace/include -I/usr/local/cuda/include' \
  --extra-ldflags='-L/app/workspace/lib -L/usr/local/cuda/lib64' \
  --extra-libs='-ldl -lpthread -lm -lz' \
  --pkgconfigdir=/app/workspace/lib/pkgconfig \
  --pkg-config-flags=--static \
  --prefix=/app/workspace \
  --enable-encoder=gif \
  --enable-decoder=gif \
  --enable-decoder=mjpeg \
  --enable-encoder=mjpeg \
  --enable-encoder=rawvideo \
  --enable-decoder=rawvideo \
  --enable-encoder=h264_vaapi \
  --enable-encoder=h264_videotoolbox \
  --enable-muxer=rawvideo \
  --enable-demuxer=rawvideo \
  --enable-muxer=mp4 \
  --enable-muxer=mjpeg \
  --enable-muxer=gif \
  --enable-demuxer=mjpeg \
  --enable-demuxer=image2 \
  --enable-demuxer=mov \
  --enable-demuxer=gif \
  --enable-protocol=file \
  --enable-filter=scale \
  --enable-filter=fps \
  --enable-filter=hwupload \
  --enable-filter=palettegen \
  --enable-filter=paletteuse \
  --enable-filter=split \
  --enable-filter=setpts \
  --enable-hwaccels

execute make -j $MJOBS
execute make install

INSTALL_FOLDER="/usr/bin"
if [[ "$OSTYPE" == "darwin"* ]]; then
  INSTALL_FOLDER="/usr/local/bin"
fi

verify_binary_type

echo ""
echo "Building done. The following binaries can be found here:"
echo "- ffmpeg: $WORKSPACE/bin/ffmpeg"
echo "- ffprobe: $WORKSPACE/bin/ffprobe"
echo "- ffplay: $WORKSPACE/bin/ffplay"
echo ""

# if [[ "$AUTOINSTALL" == "yes" ]]; then
#   if command_exists "sudo"; then
#     sudo cp "$WORKSPACE/bin/ffmpeg" "$INSTALL_FOLDER/ffmpeg"
#     sudo cp "$WORKSPACE/bin/ffprobe" "$INSTALL_FOLDER/ffprobe"
#     sudo cp "$WORKSPACE/bin/ffplay" "$INSTALL_FOLDER/ffplay"
#     echo "Done. FFmpeg is now installed to your system."
#   else
#     cp "$WORKSPACE/bin/ffmpeg" "$INSTALL_FOLDER/ffmpeg"
#     cp "$WORKSPACE/bin/ffprobe" "$INSTALL_FOLDER/ffprobe"
#     cp "$WORKSPACE/bin/ffplay" "$INSTALL_FOLDER/ffplay"
#     echo "Done. FFmpeg is now installed to your system."
#   fi
# elif [[ ! "$SKIPINSTALL" == "yes" ]]; then
#   read -r -p "Install these binaries to your $INSTALL_FOLDER folder? Existing binaries will be replaced. [Y/n] " response
#   case $response in
#   [yY][eE][sS] | [yY])
#     if command_exists "sudo"; then
#       sudo cp "$WORKSPACE/bin/ffmpeg" "$INSTALL_FOLDER/ffmpeg"
#       sudo cp "$WORKSPACE/bin/ffprobe" "$INSTALL_FOLDER/ffprobe"
#       sudo cp "$WORKSPACE/bin/ffplay" "$INSTALL_FOLDER/ffplay"
#     else
#       cp "$WORKSPACE/bin/ffmpeg" "$INSTALL_FOLDER/ffmpeg"
#       cp "$WORKSPACE/bin/ffprobe" "$INSTALL_FOLDER/ffprobe"
#       cp "$WORKSPACE/bin/ffplay" "$INSTALL_FOLDER/ffplay"
#     fi
#     echo "Done. FFmpeg is now installed to your system."
#     ;;
#   esac
# fi

exit 0
