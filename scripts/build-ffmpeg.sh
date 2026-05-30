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
export DYLD_FALLBACK_LIBRARY_PATH="${PREFIX}/lib:${DYLD_FALLBACK_LIBRARY_PATH:-/usr/local/lib:/usr/lib}"  # macOS run-time fallback
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
    # libvorbis 1.3.7's configure injects the obsolete '-force_cpusubtype_ALL' flag on macOS, which
    # the modern linker rejects (this is what broke test_sharedbook). Strip it from the generated
    # Makefiles with a portable sed (no -i); a harmless no-op on Linux where the flag isn't added.
    find . -name Makefile | while read -r f; do
      sed 's/-force_cpusubtype_ALL//g' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    done
    make -j"${JOBS}"; make install )
}
build_lame() {        # MP3 encoder — LGPL (MP3 patents expired)
  log "LAME ${LAME_VERSION} (MP3 encode, LGPL — patents expired 2017)"
  fetch_tar "https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz" lame
  # LAME 3.100 exports 'lame_init_old' in libmp3lame.sym but never defines it, which fails the macOS
  # arm64 link ("Undefined symbols: _lame_init_old"). Drop that line (portable sed; harmless elsewhere).
  sed '/lame_init_old/d' "${WORK}/lame/include/libmp3lame.sym" > "${WORK}/lame/include/libmp3lame.sym.tmp" \
    && mv "${WORK}/lame/include/libmp3lame.sym.tmp" "${WORK}/lame/include/libmp3lame.sym"
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

  # ENCODER ALLOWLIST (Axis 2): disable ALL encoders, then re-enable only royalty-free ones.
  # A denylist is unsafe — FFmpeg ships native encoders for many encumbered codecs (MPEG-4 Part 2,
  # MPEG-1/2, H.263, WMV/WMA, AC-3, ProRes) plus HW H.264/H.265 (nvenc/vaapi/vulkan/qsv/amf/mf/...).
  # The allowlist is the auditable contract: anything not listed simply cannot be produced.
  local enable_enc="libsvtav1,libaom_av1,libvpx,libvpx_vp9,ffv1,ffvhuff,huffyuv,utvideo,magicyuv,mjpeg,png,apng,gif,bmp,tiff,qoi,libwebp,libwebp_anim,rawvideo,wrapped_avframe,libopus,libvorbis,flac,alac,libmp3lame,wavpack,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s32le,pcm_f32le,pcm_u8,pcm_mulaw,pcm_alaw,ass,ssa,subrip,webvtt,mov_text,text"

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
      "${enable_libs[@]}" ${hw[@]+"${hw[@]}"} ${extra[@]+"${extra[@]}"} \
      --disable-encoders --enable-encoder="${enable_enc}" \
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
  # The binary must actually RUN — otherwise the checks below pass vacuously (this masked a
  # broken macOS build where ffmpeg couldn't load libvpx). No '|| true' here, on purpose.
  "${PREFIX}/bin/ffmpeg" -hide_banner -version >/dev/null 2>&1 \
    || die "AUDIT FAILED: ${PREFIX}/bin/ffmpeg does not run (unresolved shared library?)"
  local cfg; cfg="$("${PREFIX}/bin/ffmpeg" -hide_banner -buildconf 2>/dev/null || true)"
  if grep -qE -- '--enable-gpl|--enable-nonfree' <<<"$cfg"; then
    die "AUDIT FAILED: binary is GPL/nonfree"
  fi
  local enc; enc="$("${PREFIX}/bin/ffmpeg" -hide_banner -encoders 2>/dev/null || true)"
  # Belt to the allowlist's braces: assert no patent-encumbered ENCODER slipped through.
  local bad; bad="$(printf '%s\n' "$enc" | awk '/^ [VAS]/{print $2}' \
    | grep -iE '^(libx264|libx265|libfdk|h26[1-5]|h264_|hevc_|mpeg[124]|msmpeg4|m4v|h263|flv$|wmv[0-9]|wmav|aac|ac3|eac3|prores|dnxhd|vc1|dts|truehd)' || true)"
  if [ -n "${bad}" ]; then
    printf 'leaked encoders:\n%s\n' "${bad}"
    die "AUDIT FAILED: patent-encumbered ENCODER(s) present"
  fi
  log "AUDIT OK: LGPL, no nonfree, encoders limited to the royalty-free allowlist."
}

# ---------------------------------------------------------------------------
# Smoke test — prove the binary WORKS (not just that it lacks bad encoders): royalty-free encode
# round-trips, confirm the patent-codec DECODERS are present (decode-all), and decode real
# H.264/AAC + JPEG fixtures when CI provides them via SMOKE_H264_SAMPLE / SMOKE_JPEG_SAMPLE.
# ---------------------------------------------------------------------------
smoke_test() {
  local ff="${PREFIX}/bin/ffmpeg" fp="${PREFIX}/bin/ffprobe" t; t="$(mktemp -d)"
  local V=(-f lavfi -i testsrc=size=128x96:rate=10:duration=1)
  local A=(-f lavfi -i sine=frequency=440:duration=1)
  probe() { "$fp" -v error -select_streams "$1":0 -show_entries stream=codec_name -of csv=p=0 "$2"; }
  log "Smoke test: royalty-free encode round-trips + decode capability"

  "$ff" -hide_banner -loglevel error "${V[@]}" -c:v libsvtav1 -preset 12 -y "$t/v.mkv"
  [ "$(probe v "$t/v.mkv")" = av1 ]  || die "smoke: AV1 encode failed"
  "$ff" -hide_banner -loglevel error "${V[@]}" -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -y "$t/v.webm"
  [ "$(probe v "$t/v.webm")" = vp9 ] || die "smoke: VP9 encode failed"
  "$ff" -hide_banner -loglevel error "${A[@]}" -c:a libopus -y "$t/a.opus"
  [ "$(probe a "$t/a.opus")" = opus ] || die "smoke: Opus encode failed"
  "$ff" -hide_banner -loglevel error "${A[@]}" -c:a libmp3lame -y "$t/a.mp3"
  [ "$(probe a "$t/a.mp3")" = mp3 ]  || die "smoke: MP3 encode failed"
  "$ff" -hide_banner -loglevel error -f lavfi -i testsrc=size=128x96 -frames:v 1 -y "$t/i.jpg"
  "$ff" -hide_banner -loglevel error -i "$t/i.jpg" -frames:v 1 -y "$t/i.png"
  [ -s "$t/i.png" ] || die "smoke: JPEG encode/decode round-trip failed"

  # decode-all contract: the patent-codec DECODERS must be present
  local decs; decs="$("$ff" -hide_banner -decoders 2>/dev/null | awk '/^ [VAS]/{print $2}')"
  for d in h264 hevc aac; do grep -qx "$d" <<<"$decs" || die "smoke: '$d' decoder missing"; done

  # decode REAL patent-codec input when CI provides fixtures (proves "reads any MP4")
  if [ -n "${SMOKE_H264_SAMPLE:-}" ] && [ -f "${SMOKE_H264_SAMPLE}" ]; then
    "$ff" -hide_banner -loglevel error -i "${SMOKE_H264_SAMPLE}" -frames:v 1 -y "$t/h264.png"
    [ -s "$t/h264.png" ] || die "smoke: H.264/AAC sample decode failed"
    log "smoke: decoded real H.264/AAC sample OK"
  fi
  if [ -n "${SMOKE_JPEG_SAMPLE:-}" ] && [ -f "${SMOKE_JPEG_SAMPLE}" ]; then
    "$ff" -hide_banner -loglevel error -i "${SMOKE_JPEG_SAMPLE}" -frames:v 1 -y "$t/jpg.png"
    [ -s "$t/jpg.png" ] || die "smoke: JPEG sample decode failed"
  fi
  rm -rf "$t"
  log "SMOKE OK: encodes AV1/VP9/Opus/MP3/JPEG; H.264/HEVC/AAC decoders present."
}

# ---------------------------------------------------------------------------
# Make installed pkg-config files relocatable so the .deb/tarball work from any install location
# (e.g. /opt/ffmpeg-free) without a manual prefix fixup — e.g. when building OpenCV against
# ffmpeg-free. Rewrites the absolute build prefix to pkg-config's ${pcfiledir} anchor.
# ---------------------------------------------------------------------------
relocatable_pkgconfig() {
  local d="${PREFIX}/lib/pkgconfig" pc
  [ -d "$d" ] || return 0
  for pc in "$d"/*.pc; do
    [ -f "$pc" ] || continue
    sed -e "s|${PREFIX}|\${pcfiledir}/../..|g" \
        -e 's|^prefix=.*|prefix=${pcfiledir}/../..|' "$pc" > "$pc.tmp" && mv "$pc.tmp" "$pc"
  done
  log "pkg-config files made relocatable (prefix=\${pcfiledir}/../..)"
}

# ---------------------------------------------------------------------------
# Make the binaries/libraries relocatable so the tarball/.deb run from any location.
#   Linux : $ORIGIN-relative rpath via patchelf.
#   macOS : rewrite each dylib id + every reference into our prefix to @rpath, and add
#           @loader_path rpaths. (libvpx installs a BARE install_name that dyld can't resolve,
#           which silently broke every macOS ffmpeg until the smoke test caught it.)
# ---------------------------------------------------------------------------
make_relocatable() {
  case "$(uname -s)" in
    Linux)
      command -v patchelf >/dev/null 2>&1 || { log "WARN: patchelf missing; tarball not relocatable"; return 0; }
      find "${PREFIX}/bin" -type f -exec patchelf --set-rpath '$ORIGIN/../lib' {} + 2>/dev/null || true
      ;;
    Darwin)
      local f base dep
      for f in "${PREFIX}"/lib/*.dylib; do
        [ -f "$f" ] || continue
        install_name_tool -id "@rpath/$(basename "$f")" "$f" 2>/dev/null || true
      done
      for f in "${PREFIX}"/bin/* "${PREFIX}"/lib/*.dylib; do
        [ -f "$f" ] || continue
        while IFS= read -r dep; do
          base="$(basename "$dep")"
          if [[ "$dep" == "${PREFIX}/"* ]] || { [[ "$dep" != /* && "$dep" != @* ]] && [ -e "${PREFIX}/lib/${base}" ]; }; then
            install_name_tool -change "$dep" "@rpath/${base}" "$f" 2>/dev/null || true
          fi
        done < <(otool -L "$f" 2>/dev/null | awk 'NR>1{print $1}')
      done
      for f in "${PREFIX}"/bin/*;      do [ -f "$f" ] && install_name_tool -add_rpath "@loader_path/../lib" "$f" 2>/dev/null || true; done
      for f in "${PREFIX}"/lib/*.dylib; do [ -f "$f" ] && install_name_tool -add_rpath "@loader_path"      "$f" 2>/dev/null || true; done
      # install_name_tool invalidates the code signature; re-sign ad-hoc or arm64 macOS SIGKILLs it.
      for f in "${PREFIX}"/bin/* "${PREFIX}"/lib/*.dylib; do
        [ -f "$f" ] && codesign --force --sign - "$f" 2>/dev/null || true
      done
      ;;
  esac
  log "Made binaries/libraries relocatable ($(uname -s))"
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
make_relocatable
relocatable_pkgconfig
write_buildinfo
audit
smoke_test
log "Done. Staged in ${PREFIX}"
