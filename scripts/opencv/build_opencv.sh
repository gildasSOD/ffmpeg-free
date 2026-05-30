#!/usr/bin/env bash
#
# build_opencv.sh — build OpenCV (+contrib, +CUDA) linked against the royalty-free FFmpeg
# (ffmpeg-free), so cv::VideoWriter/VideoCapture can only ENCODE royalty-free codecs.
#
# Lineage: a cleaned, parameterized descendant of mdegans/nano_build_opencv, retargeted at
# JetPack 6.2 / Jetson Orin (Ubuntu 22.04, CUDA 12.6, SM 8.7) and de-coupled from the distro
# GPL FFmpeg. Runs both on-device (uses sudo) and in a container (as root, non-interactive).
#
# ROYALTY-FREE: links ffmpeg-free instead of Ubuntu's GPL FFmpeg, never installs
# libx264/libxvid/libavcodec-dev, and sets OPENCV_ENABLE_NONFREE=OFF (that flag enables the
# patented SURF in opencv_contrib). See the repo README for the rationale.
#
# Usage:
#   sudo ./build_opencv.sh                          # defaults, install deps, build, install
#   OPENCV_VERSION=4.13.0 JOBS=4 ./build_opencv.sh
#   INSTALL_DEPS=0 WITH_CONTRIB=OFF HEADLESS=1 ./build_opencv.sh
#
# Tunables (env vars; shown with defaults):
#   OPENCV_VERSION=4.13.0     OpenCV + opencv_contrib git tag (>= 4.13.0 REQUIRED: older OpenCV
#                             uses avcodec_close/av_stream_get_side_data, removed in FFmpeg 7/8)
#   PREFIX=/usr/local         install prefix
#   FFMPEG_FREE_PREFIX=/opt/ffmpeg-free   where `apt install ffmpeg-free` put it
#   BUILD_DIR=$HOME/opencv_build   on-disk build dir (NOT /tmp — that is often tmpfs/RAM)
#   JOBS=<auto>               parallel jobs (auto = min(cores, (RAM+swap)/2GB))
#   CUDA_ARCH_BIN=8.7         Orin=8.7, Xavier=7.2, desktop varies; '' to skip
#   WITH_CUDA=ON  WITH_CONTRIB=ON  WITH_PYTHON=ON  WITH_GSTREAMER=ON
#   HEADLESS=0                1 = no GTK/QT/OpenGL (containers / headless servers)
#   INSTALL_DEPS=1  KEEP_BUILD=0
set -euo pipefail

OPENCV_VERSION="${OPENCV_VERSION:-4.13.0}"
PREFIX="${PREFIX:-/usr/local}"
FFMPEG_FREE_PREFIX="${FFMPEG_FREE_PREFIX:-/opt/ffmpeg-free}"
BUILD_DIR="${BUILD_DIR:-${HOME:-/root}/opencv_build}"
CUDA_ARCH_BIN="${CUDA_ARCH_BIN:-8.7}"
WITH_CUDA="${WITH_CUDA:-ON}"
WITH_CONTRIB="${WITH_CONTRIB:-ON}"
WITH_PYTHON="${WITH_PYTHON:-ON}"
WITH_GSTREAMER="${WITH_GSTREAMER:-ON}"
HEADLESS="${HEADLESS:-0}"
INSTALL_DEPS="${INSTALL_DEPS:-1}"
KEEP_BUILD="${KEEP_BUILD:-0}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"

detect_jobs() {
  [ -n "${JOBS:-}" ] && { log "Using JOBS=${JOBS}"; return; }
  local cores mem_kb mem_gb cap
  cores="$(nproc)"
  mem_kb="$(awk '/MemTotal/{m=$2} /SwapTotal/{s=$2} END{print m+s}' /proc/meminfo 2>/dev/null || echo 4000000)"
  mem_gb=$(( mem_kb / 1024 / 1024 )); [ "$mem_gb" -lt 1 ] && mem_gb=1
  cap=$(( mem_gb / 2 )); [ "$cap" -lt 1 ] && cap=1            # OpenCV+CUDA ~2 GB/job
  JOBS=$(( cores < cap ? cores : cap ))
  log "Auto JOBS=${JOBS} (cores=${cores}, RAM+swap≈${mem_gb} GB). On 8 GB Orin Nano add zram/swap for more."
}

install_deps() {
  [ "$INSTALL_DEPS" = "1" ] || { log "INSTALL_DEPS=0 — skipping apt"; return; }
  log "Installing build deps (deliberately NO distro FFmpeg / x264 / xvid)"
  $SUDO apt-get update
  $SUDO apt-get install -y --no-install-recommends \
    build-essential cmake git pkg-config gfortran ca-certificates curl \
    libeigen3-dev libtbb-dev libtbb12 \
    libatlas-base-dev libopenblas-dev liblapack-dev liblapacke-dev \
    libjpeg-dev libpng-dev libtiff-dev libwebp-dev \
    libv4l-dev v4l-utils \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libgstreamer-plugins-good1.0-dev
  if [ "$HEADLESS" != "1" ]; then
    $SUDO apt-get install -y --no-install-recommends \
      libgtk-3-dev libcanberra-gtk3-module libglew-dev libgl1-mesa-dev libglu1-mesa-dev
  fi
  if [ "$WITH_PYTHON" = "ON" ]; then
    $SUDO apt-get install -y --no-install-recommends python3-dev python3-numpy
  fi
}

fetch_sources() {
  mkdir -p "${BUILD_DIR}"; cd "${BUILD_DIR}"
  [ -d opencv ] || git clone --depth 1 --branch "${OPENCV_VERSION}" https://github.com/opencv/opencv.git
  if [ "${WITH_CONTRIB}" = "ON" ] && [ ! -d opencv_contrib ]; then
    git clone --depth 1 --branch "${OPENCV_VERSION}" https://github.com/opencv/opencv_contrib.git
  fi
}

configure() {
  [ -f "${FFMPEG_FREE_PREFIX}/lib/pkgconfig/libavcodec.pc" ] \
    || die "ffmpeg-free not found at ${FFMPEG_FREE_PREFIX}. Install it (apt install ffmpeg-free, or the
       .deb from the Release), or set FFMPEG_FREE_PREFIX. We must NOT fall back to the distro FFmpeg."
  export PKG_CONFIG_PATH="${FFMPEG_FREE_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
  log "FFmpeg via pkg-config: $(pkg-config --modversion libavcodec) from ${FFMPEG_FREE_PREFIX}"

  local flags=(
    -D CMAKE_BUILD_TYPE=Release
    -D CMAKE_INSTALL_PREFIX="${PREFIX}"
    -D CMAKE_INSTALL_RPATH="${FFMPEG_FREE_PREFIX}/lib;${PREFIX}/lib"
    -D CMAKE_INSTALL_RPATH_USE_LINK_PATH=ON
    -D OPENCV_GENERATE_PKGCONFIG=ON
    -D BUILD_EXAMPLES=OFF -D BUILD_TESTS=OFF -D BUILD_PERF_TESTS=OFF
    -D OPENCV_ENABLE_NONFREE=OFF
    -D WITH_FFMPEG=ON
    -D WITH_GSTREAMER="${WITH_GSTREAMER}"
    -D WITH_V4L=ON -D WITH_LIBV4L=ON
    -D WITH_TBB=ON
  )
  if [ "${WITH_CUDA}" = "ON" ]; then
    flags+=( -D WITH_CUDA=ON -D CUDA_ARCH_PTX= -D CUDA_FAST_MATH=ON
             -D WITH_CUBLAS=ON -D WITH_CUDNN=ON -D OPENCV_DNN_CUDA=ON -D ENABLE_NEON=ON )
    [ -n "${CUDA_ARCH_BIN}" ] && flags+=( -D CUDA_ARCH_BIN="${CUDA_ARCH_BIN}" )
  fi
  [ "${WITH_CONTRIB}" = "ON" ] && flags+=( -D OPENCV_EXTRA_MODULES_PATH="${BUILD_DIR}/opencv_contrib/modules" )
  [ "${WITH_PYTHON}" = "ON" ] && flags+=( -D BUILD_opencv_python3=ON ) || flags+=( -D BUILD_opencv_python3=OFF )
  if [ "${HEADLESS}" = "1" ]; then
    flags+=( -D WITH_GTK=OFF -D WITH_QT=OFF -D WITH_OPENGL=OFF )
  else
    flags+=( -D WITH_GTK=ON -D WITH_OPENGL=ON )
  fi

  mkdir -p "${BUILD_DIR}/opencv/build"; cd "${BUILD_DIR}/opencv/build"
  cmake "${flags[@]}" .. 2>&1 | tee configure.log
  grep -E 'FFMPEG|GStreamer' configure.log || true
}

build_and_install() {
  cd "${BUILD_DIR}/opencv/build"
  log "Building OpenCV ${OPENCV_VERSION} with -j${JOBS} (CUDA builds are long — be patient)"
  make -j"${JOBS}" 2>&1 | tee build.log
  if [ -w "${PREFIX}" ]; then make install 2>&1 | tee install.log
  else $SUDO make install 2>&1 | tee install.log; fi
  echo "${PREFIX}/lib"            | $SUDO tee /etc/ld.so.conf.d/opencv.conf >/dev/null
  echo "${FFMPEG_FREE_PREFIX}/lib"| $SUDO tee /etc/ld.so.conf.d/ffmpeg-free.conf >/dev/null
  $SUDO ldconfig
}

verify() {
  log "Verifying the FFmpeg backend is ffmpeg-free (not the distro one)…"
  local lib; lib="$(ls -1 "${PREFIX}"/lib/libopencv_videoio.so* 2>/dev/null | head -n1 || true)"
  [ -n "$lib" ] || die "libopencv_videoio not found under ${PREFIX}/lib"
  if ldd "$lib" | grep -q "${FFMPEG_FREE_PREFIX}/lib/libavcodec"; then
    log "OK: $(basename "$lib") links ${FFMPEG_FREE_PREFIX}/lib/libavcodec"
  else
    ldd "$lib" | grep -i avcodec || true
    die "libopencv_videoio does NOT link ffmpeg-free — it found another libavcodec. Check PKG_CONFIG_PATH."
  fi
  # ffmpeg-free itself is audited to contain no patent-codec encoders, so an OpenCV linked to it
  # cannot emit H.264/H.265/AAC. Surface the FFmpeg line OpenCV recorded:
  grep -E 'FFMPEG:' "${BUILD_DIR}/opencv/build/configure.log" 2>/dev/null || true
}

main() {
  detect_jobs
  install_deps
  fetch_sources
  configure
  build_and_install
  verify
  if [ "${KEEP_BUILD}" = "1" ]; then log "KEEP_BUILD=1 — leaving ${BUILD_DIR}"; else rm -rf "${BUILD_DIR}"; fi
  log "Done. OpenCV ${OPENCV_VERSION} installed to ${PREFIX}, video I/O linked against ffmpeg-free."
  log "In code: cv::VideoWriter(path, cv::CAP_FFMPEG, fourcc('a','v','0','1'), fps, size)  // AV1, royalty-free"
}
main "$@"
