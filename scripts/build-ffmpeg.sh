#!/usr/bin/env bash
#
# build-ffmpeg.sh — build a royalty-free FFmpeg (and its codec libraries) from pinned source.
#
# Closes BOTH legal axes (see README.md):
#   Axis 1 (copyright): --disable-gpl --disable-nonfree, shared/dynamic, LGPL-2.1+.
#   Axis 2 (patents):   encodes only royalty-free codecs; H.264/H.265/AAC encoders disabled.
#
# Usage:
#   PLATFORM={macos|linux|linux-cuda|jetson} PROFILE={decode-all|strict-rf} \
#   PREFIX=/path/to/staging ./scripts/build-ffmpeg.sh
#
# Build tools are expected to be installed by the caller/CI (nasm, cmake, meson, ninja,
# pkg-config, autoconf, libtool, git, curl, a C/C++ toolchain; clang for linux-cuda).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${HERE}/versions.env"

PLATFORM="${PLATFORM:?set PLATFORM=macos|linux|linux-cuda|jetson}"
PROFILE="${PROFILE:-decode-all}"
PREFIX="${PREFIX:-${PWD}/staging}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
WORK="${WORK:-${PWD}/build-work}"
SRC_CACHE="${WORK}/src"

mkdir -p "${PREFIX}" "${WORK}" "${SRC_CACHE}"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
export PATH="${PREFIX}/bin:${PATH}"
export LD_LIBRARY_PATH="${PREFIX}/lib:${LD_LIBRARY_PATH:-}"
CFLAGS_EXTRA="-I${PREFIX}/include"
LDFLAGS_EXTRA="-L${PREFIX}/lib"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

fetch_tar() {  # url  dirname
  local url="$1" dir="$2" base; base="$(basename "$url")"
  [ -f "${SRC_CACHE}/${base}" ] || curl -fSL --retry 3 -o "${SRC_CACHE}/${base}" "$url"
  rm -rf "${WORK}/${dir}"; mkdir -p "${WORK}/${dir}"
  tar -xf "${SRC_CACHE}/${base}" -C "${WORK}/${dir}" --strip-components=1
}
fetch_git() {  # repo  tag  dirname
  local repo="$1" tag="$2" dir="$3"
  rm -rf "${WORK}/${dir}"
  git clone --depth 1 --branch "$tag" "$repo" "${WORK}/${dir}"
}

# ---------------------------------------------------------------------------
# Codec libraries (all permissively licensed; none triggers GPL/nonfree).
# ---------------------------------------------------------------------------
build_dav1d() {       # AV1 decoder — meson
  log "dav1d ${DAV1D_VERSION} (AV1 decode, BSD-2-Clause)"
  fetch_git "https://code.videolan.org/videolan/dav1d.git" "${DAV1D_VERSION}" dav1d
  ( cd "${WORK}/dav1d"
    meson setup build --prefix="${PREFIX}" --libdir=lib --buildtype=release \
      -Denable_tools=false -Denable_tests=false -Ddefault_library=shared
    ninja -C build -j"${JOBS}"; ninja -C build install )
}
build_svtav1() {      # AV1 encoder (fast) — cmake
  log "SVT-AV1 ${SVTAV1_VERSION} (AV1 encode, BSD-3-Clause-Clear + AOM Patent License 1.0)"
  fetch_git "https://gitlab.com/AOMediaCodec/SVT-AV1.git" "v${SVTAV1_VERSION}" svtav1
  ( cd "${WORK}/svtav1"
    cmake -S . -B build -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF -DBUILD_APPS=OFF
    cmake --build build -j"${JOBS}"; cmake --install build )
}
build_aom() {         # AV1 reference enc/dec — cmake
  log "libaom ${AOM_VERSION} (AV1 reference, BSD-2-Clause + AOM Patent License 1.0)"
  fetch_git "https://aomedia.googlesource.com/aom" "v${AOM_VERSION}" aom
  ( cd "${WORK}/aom"
    cmake -S . -B build -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DENABLE_TESTS=0 -DENABLE_TOOLS=0 -DENABLE_EXAMPLES=0
    cmake --build build -j"${JOBS}"; cmake --install build )
}
build_vpx() {         # VP8/VP9 — autotools
  log "libvpx ${LIBVPX_VERSION} (VP8/VP9, BSD-3-Clause + Google patent grant)"
  fetch_git "https://github.com/webmproject/libvpx.git" "v${LIBVPX_VERSION}" vpx
  ( cd "${WORK}/vpx"
    ./configure --prefix="${PREFIX}" --enable-shared --disable-static --disable-examples \
      --disable-unit-tests --enable-vp9-highbitdepth --as=$(command -v nasm yasm | head -n1 | xargs basename 2>/dev/null || echo nasm)
    make -j"${JOBS}"; make install )
}
build_opus() {        # Opus — autotools
  log "Opus ${OPUS_VERSION} (BSD-3-Clause; royalty-free patent grants)"
  fetch_tar "https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz" opus
  ( cd "${WORK}/opus"; ./configure --prefix="${PREFIX}" --enable-shared --disable-static
    make -j"${JOBS}"; make install )
}
build_ogg_vorbis() {  # Ogg + Vorbis — autotools
  log "libogg ${OGG_VERSION} + libvorbis ${VORBIS_VERSION} (BSD-3-Clause)"
  fetch_tar "https://downloads.xiph.org/releases/ogg/libogg-${OGG_VERSION}.tar.gz" ogg
  ( cd "${WORK}/ogg"; ./configure --prefix="${PREFIX}" --enable-shared --disable-static
    make -j"${JOBS}"; make install )
  fetch_tar "https://downloads.xiph.org/releases/vorbis/libvorbis-${VORBIS_VERSION}.tar.gz" vorbis
  ( cd "${WORK}/vorbis"; ./configure --prefix="${PREFIX}" --enable-shared --disable-static \
      --with-ogg="${PREFIX}"
    # Build/install only the library + headers + .pc files via per-directory make. The test/ dir's
    # test_sharedbook fails to link on clang/arm64 (macOS); a command-line `make SUBDIRS=` override
    # can't be used because it propagates into sub-makes and breaks recursion (cd into a missing dir).
    make -j"${JOBS}" -C lib
    make -C lib install
    make -C include install
    install -d "${PREFIX}/lib/pkgconfig"
    cp -f vorbis.pc vorbisenc.pc vorbisfile.pc "${PREFIX}/lib/pkgconfig/" )
}
build_lame() {        # MP3 encoder — LGPL (MP3 patents expired)
  log "LAME ${LAME_VERSION} (MP3 encode, LGPL — patents expired 2017)"
  fetch_tar "https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz" lame
  ( cd "${WORK}/lame"; ./configure --prefix="${PREFIX}" --enable-shared --disable-static --disable-frontend
    make -j"${JOBS}"; make install )
}
build_webp() {        # WebP — autotools
  log "libwebp ${LIBWEBP_VERSION} (BSD-3-Clause + Google patent grant)"
  fetch_tar "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${LIBWEBP_VERSION}.tar.gz" webp
  ( cd "${WORK}/webp"; ./configure --prefix="${PREFIX}" --enable-shared --disable-static
    make -j"${JOBS}"; make install )
}
build_nvcodec_headers() {  # MIT NVENC/NVDEC headers (free path; GPU via user's driver)
  log "nv-codec-headers ${NVCODEC_HEADERS_VERSION} (MIT)"
  fetch_git "https://github.com/FFmpeg/nv-codec-headers.git" "n${NVCODEC_HEADERS_VERSION}" nvcodec
  ( cd "${WORK}/nvcodec"; make PREFIX="${PREFIX}" install )
}

# ---------------------------------------------------------------------------
# FFmpeg
# ---------------------------------------------------------------------------
build_ffmpeg() {
  log "FFmpeg ${FFMPEG_VERSION} — profile=${PROFILE} platform=${PLATFORM}"
  fetch_tar "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" ffmpeg
  cp -f "${SRC_CACHE}/ffmpeg-${FFMPEG_VERSION}.tar.xz" "${PREFIX}/../" 2>/dev/null || true  # keep for LGPL source offer

  # Royalty-free encoders to enable (all RF / LGPL-compatible).
  local enable_libs=(
    --enable-libsvtav1 --enable-libaom --enable-libdav1d
    --enable-libvpx --enable-libopus --enable-libvorbis
    --enable-libwebp --enable-libmp3lame
  )

  # Encoders we always remove so HW accel can't smuggle a patent codec back in (Axis 2).
  local disable_enc="h264_nvenc,hevc_nvenc,h264_videotoolbox,hevc_videotoolbox,h264_qsv,hevc_qsv,h264_vaapi,hevc_vaapi,h264_amf,hevc_amf,h264_mf,hevc_mf,h264_v4l2m2m,hevc_v4l2m2m,h264_vulkan,hevc_vulkan,aac,aac_at,aac_mf"

  # Per-platform hardware flags. NOTE: the free CUDA path only — never --enable-libnpp /
  # --enable-cuda-nvcc / --enable-cuda-sdk (FFmpeg "nonfree" → unredistributable).
  local hw=()
  case "${PLATFORM}" in
    macos)      hw=(--enable-videotoolbox) ;;
    linux)      hw=() ;;  # generic; add --enable-vaapi if libva is present
    linux-cuda) build_nvcodec_headers
                # NVENC/NVDEC/cuvid via the MIT ffnvcodec headers — the royalty-free HW path.
                # --enable-cuda-llvm (compiles the bundled CUDA *filters* with clang) is a v1 TODO:
                # it needs a verified clang+CUDA toolchain and is NOT required for HW encode/decode.
                hw=(--enable-ffnvcodec --enable-cuvid --enable-nvdec --enable-nvenc)
                [ -d /usr/local/cuda/include ] && CFLAGS_EXTRA="${CFLAGS_EXTRA} -I/usr/local/cuda/include"
                [ -d /usr/local/cuda/lib64 ]   && LDFLAGS_EXTRA="${LDFLAGS_EXTRA} -L/usr/local/cuda/lib64" ;;
    jetson)     # Tegra HW codecs use V4L2 M2M / NVMPI. Real Jetson HW enc/dec needs out-of-tree
                # patches (e.g. jocover/jetson-ffmpeg) — TODO. v1 builds in the L4T container with
                # software codecs; v4l2-m2m is left to configure autodetect (so a missing header
                # can't fail the build), and NVMPI integration is the documented follow-up.
                hw=() ;;
    *) die "unknown PLATFORM=${PLATFORM}" ;;
  esac

  # strict-rf: also remove patent-codec DECODERS (representative set) for provably zero patent contact.
  local extra=()
  if [ "${PROFILE}" = "strict-rf" ]; then
    extra+=( --disable-decoder=h264,hevc,aac,aac_latm,ac3,eac3,mpeg2video,mpeg4,msmpeg4v1,msmpeg4v2,msmpeg4v3,vc1,wmv3
             --disable-parser=h264,hevc,aac,ac3,mpeg4video
             --disable-hwaccels )
    log "strict-rf: patent-codec decoders/parsers/hwaccels removed"
  fi

  ( cd "${WORK}/ffmpeg"
    ./configure \
      --prefix="${PREFIX}" \
      --disable-gpl --disable-nonfree \
      --enable-shared --disable-static --enable-pic \
      --disable-doc --disable-debug \
      --disable-ffplay \
      "${enable_libs[@]}" "${hw[@]}" "${extra[@]}" \
      --disable-encoder="${disable_enc}" \
      --extra-cflags="${CFLAGS_EXTRA}" \
      --extra-ldflags="${LDFLAGS_EXTRA}"
    make -j"${JOBS}"
    make install )
}

write_buildinfo() {
  mkdir -p "${PREFIX}/share/ffmpeg-free"
  {
    echo "ffmpeg-free build"
    echo "date_utc: ${BUILD_DATE:-unknown}"   # pass BUILD_DATE from CI; scripts can't read the clock here
    echo "platform: ${PLATFORM}"
    echo "profile:  ${PROFILE}"
    echo "ffmpeg:   ${FFMPEG_VERSION}"
    echo "deps: dav1d=${DAV1D_VERSION} svtav1=${SVTAV1_VERSION} aom=${AOM_VERSION} vpx=${LIBVPX_VERSION} opus=${OPUS_VERSION} vorbis=${VORBIS_VERSION} lame=${LAME_VERSION} webp=${LIBWEBP_VERSION}"
  } > "${PREFIX}/share/ffmpeg-free/BUILDINFO.txt"
  "${PREFIX}/bin/ffmpeg" -hide_banner -version | head -n1 >> "${PREFIX}/share/ffmpeg-free/BUILDINFO.txt" || true
}

# ---------------------------------------------------------------------------
# Audit — the build's promise must be provable (README §5).
# ---------------------------------------------------------------------------
audit() {
  log "Auditing ${PREFIX}/bin/ffmpeg"
  local cfg; cfg="$("${PREFIX}/bin/ffmpeg" -hide_banner -buildconf 2>/dev/null || true)"
  if grep -qE -- '--enable-gpl|--enable-nonfree' <<<"$cfg"; then
    die "AUDIT FAILED: binary is GPL/nonfree"
  fi
  local enc; enc="$("${PREFIX}/bin/ffmpeg" -hide_banner -encoders 2>/dev/null || true)"
  # Match encoder column entries for the patent codecs (word-boundary on codec id).
  if grep -qiE '(^| )(libx264|libx265|h264_|hevc_|nvenc.*264|aac($| )|aac_)' <<<"$enc"; then
    printf '%s\n' "$enc" | grep -iE 'h264|hevc|265|aac' || true
    die "AUDIT FAILED: a patent-codec ENCODER is present"
  fi
  log "AUDIT OK: LGPL, no nonfree, no H.264/H.265/AAC encoders."
}

build_dav1d
build_svtav1
build_aom
build_vpx
build_opus
build_ogg_vorbis
build_lame
build_webp
build_ffmpeg
write_buildinfo
audit
log "Done. Staged in ${PREFIX}"
