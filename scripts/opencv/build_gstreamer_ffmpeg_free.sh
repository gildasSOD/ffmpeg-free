#!/usr/bin/env bash
#
# build_gstreamer_ffmpeg_free.sh — rebuild the GStreamer↔FFmpeg bridge plugin (gst-libav,
# which provides avenc_*/avdec_*) against the royalty-free FFmpeg, so GStreamer pipelines that
# use FFmpeg codecs route through ffmpeg-free (royalty-free encoders only).
#
# IMPORTANT compatibility reality
# --------------------------------
# gst-libav links the GStreamer CORE, so it must be built at (≈) your system GStreamer version —
# but old gst-libav does NOT compile against FFmpeg 8. Rough support: FFmpeg 8 needs gst-libav
# >= ~1.26; FFmpeg 7 >= ~1.24. JetPack 6.2 ships GStreamer 1.20, whose NVIDIA plugins (nvv4l2*,
# nvarguscamerasrc) are pinned to 1.20. You cannot put a 1.26 gst-libav into a 1.20 stack, nor
# compile 1.20 gst-libav against FFmpeg 8.
#
# => On Jetson, DON'T fight this. Use the system GStreamer 1.20 for HARDWARE INPUT (HW decode /
#    cameras — decode-side, low royalty risk) and use OpenCV's CAP_FFMPEG backend (ffmpeg-free)
#    for royalty-free ENCODE/output. See scripts/opencv/README.md. This script will refuse the
#    known-broken combo unless you set FORCE=1.
#
# On generic Linux where you control the whole GStreamer stack (>= 1.24/1.26), this builds and
# installs gst-libav against ffmpeg-free cleanly.
#
# Usage:
#   FFMPEG_FREE_PREFIX=/opt/ffmpeg-free ./build_gstreamer_ffmpeg_free.sh
#   GSTLIBAV_VERSION=1.26.0 ./build_gstreamer_ffmpeg_free.sh          # override
set -euo pipefail

FFMPEG_FREE_PREFIX="${FFMPEG_FREE_PREFIX:-/opt/ffmpeg-free}"
FORCE="${FORCE:-0}"
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"

command -v pkg-config >/dev/null || die "pkg-config required"
[ -f "${FFMPEG_FREE_PREFIX}/lib/pkgconfig/libavcodec.pc" ] || die "ffmpeg-free not at ${FFMPEG_FREE_PREFIX}"
export PKG_CONFIG_PATH="${FFMPEG_FREE_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

GST_VER="$(pkg-config --modversion gstreamer-1.0 2>/dev/null || echo 0.0.0)"
AVCODEC_MAJOR="$(pkg-config --modversion libavcodec | cut -d. -f1)"   # FFmpeg 8.x => 62
GSTLIBAV_VERSION="${GSTLIBAV_VERSION:-$GST_VER}"
gst_minor() { echo "$1" | awk -F. '{print $1*100+$2}'; }   # 1.20.x -> 120

log "System GStreamer: ${GST_VER}    ffmpeg-free libavcodec major: ${AVCODEC_MAJOR}"

# Known-incompatible: FFmpeg >= 7 (avcodec >= 61) with a GStreamer core older than 1.24.
if [ "${AVCODEC_MAJOR}" -ge 61 ] && [ "$(gst_minor "$GST_VER")" -lt 124 ]; then
  warn "GStreamer ${GST_VER} + FFmpeg (avcodec ${AVCODEC_MAJOR}) is the incompatible combo."
  warn "A gst-libav new enough for this FFmpeg won't load in GStreamer ${GST_VER} (e.g. JetPack 6.2)."
  warn "Recommended: keep system GStreamer for HW input; do royalty-free ENCODE via OpenCV CAP_FFMPEG."
  warn "See scripts/opencv/README.md → 'GStreamer on Jetson'."
  [ "${FORCE}" = "1" ] || die "Refusing to build a broken plugin. Set FORCE=1 to override (expect failure)."
fi

log "Installing meson/ninja + GStreamer dev headers"
$SUDO apt-get update
$SUDO apt-get install -y --no-install-recommends \
  build-essential meson ninja-build pkg-config bison flex \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev curl xz-utils ca-certificates

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
log "Fetching gst-libav ${GSTLIBAV_VERSION}"
curl -fSL --retry 3 -o "$WORK/gst-libav.tar.xz" \
  "https://gstreamer.freedesktop.org/src/gst-libav/gst-libav-${GSTLIBAV_VERSION}.tar.xz"
mkdir -p "$WORK/src"; tar -xf "$WORK/gst-libav.tar.xz" -C "$WORK/src" --strip-components=1

# Install into the system GStreamer plugin dir so it replaces the distro gst-libav.
PLUGINDIR="$(pkg-config --variable=pluginsdir gstreamer-1.0)"
log "Building gst-libav against ffmpeg-free → plugin dir ${PLUGINDIR}"
( cd "$WORK/src"
  meson setup build --prefix=/usr --libdir="$(dirname "$PLUGINDIR")" --buildtype=release
  ninja -C build )
# Back up the existing plugin, then install ours.
if [ -f "${PLUGINDIR}/libgstlibav.so" ]; then
  $SUDO cp -n "${PLUGINDIR}/libgstlibav.so" "${PLUGINDIR}/libgstlibav.so.distro-backup" || true
fi
$SUDO install -m644 "$WORK/src/build/ext/libav/libgstlibav.so" "${PLUGINDIR}/libgstlibav.so"
$SUDO ldconfig || true

log "Verifying the installed plugin links ffmpeg-free:"
ldd "${PLUGINDIR}/libgstlibav.so" | grep -E 'avcodec|avformat' || true
ldd "${PLUGINDIR}/libgstlibav.so" | grep -q "${FFMPEG_FREE_PREFIX}/lib/libavcodec" \
  && log "OK: gst-libav now links ${FFMPEG_FREE_PREFIX}" \
  || warn "gst-libav did not link ffmpeg-free — check PKG_CONFIG_PATH / rerun."

cat <<EOF

Done. Royalty-free runtime notes:
  - Do NOT install gstreamer1.0-plugins-ugly (that adds x264enc/x265enc).
  - Avoid HW H.264/H.265 encoder elements (e.g. nvv4l2h264enc) — those are patent-encumbered.
  - Encode with avenc_av1 / avenc_libvpx-vp9 / vp8enc / avenc_libopus instead.
  - Verify an encoder is available: gst-inspect-1.0 avenc_av1
EOF
