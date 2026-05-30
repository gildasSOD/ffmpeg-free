# Royalty-free OpenCV (linked against ffmpeg-free)

Build OpenCV so its video I/O uses **[ffmpeg-free](../../README.md)** instead of the distro's GPL
FFmpeg. Then `cv::VideoWriter` **physically cannot** emit H.264/H.265/MPEG-4/AAC — only royalty-free
codecs (AV1, VP9, Opus, MJPEG, …) — because those encoders aren't in the linked library.

## Why a stock OpenCV isn't enough
`apt install libopencv-dev` / `pip install opencv-python` link the **GPL** FFmpeg built with
`libx264`/`libx265`, so their `VideoWriter` *can* produce H.264 → patent/royalty exposure. The fix is
to **rebuild OpenCV against ffmpeg-free** and drop the patent encoders from the build deps.

## Files
| File | Purpose |
|---|---|
| `build_opencv.sh` | Clean, parameterized OpenCV+CUDA+contrib build linked to ffmpeg-free. **Supersedes** `build_opencv_jetpack62_temporary.sh` (delete that once happy). |
| `build_gstreamer_ffmpeg_free.sh` | Rebuild GStreamer's `gst-libav` (avenc_*/avdec_*) against ffmpeg-free — see the Jetson caveat below. |
| `Dockerfile.jetson` | Reproducible image: `l4t-jetpack:r36` → ffmpeg-free → OpenCV (skips the multi-hour on-device build). |
| `../../.github/workflows/opencv-jetson.yml` | Manual CI that builds & publishes the Jetson image to ghcr. |

## Quick start — on a Jetson (Orin / JetPack 6.2)
```bash
# 1) install ffmpeg-free (royalty-free FFmpeg)
curl -fsSL https://gildassod.github.io/ffmpeg-free/key.gpg | sudo tee /usr/share/keyrings/ffmpeg-free.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/ffmpeg-free.gpg] https://gildassod.github.io/ffmpeg-free stable main" \
  | sudo tee /etc/apt/sources.list.d/ffmpeg-free.list
sudo apt update && sudo apt install ffmpeg-free

# 2) build OpenCV against it (auto-detects jobs; add zram/swap on an 8 GB Nano for more)
sudo ./build_opencv.sh                       # or: OPENCV_VERSION=4.13.0 JOBS=4 ./build_opencv.sh
```
The script verifies that `libopencv_videoio` links `/opt/ffmpeg-free/lib/libavcodec` and fails if it
accidentally picked up the distro FFmpeg. All knobs are env vars (see the header of `build_opencv.sh`).

## Prebuilt image (skip the build)
```bash
docker run --rm --runtime nvidia ghcr.io/gildassod/opencv-free-jetson:latest \
  python3 -c "import cv2; print(cv2.getBuildInformation())"
```
Build it yourself / in CI: `docker buildx build -f scripts/opencv/Dockerfile.jetson .` or run the
**opencv-jetson** workflow (Actions → Run workflow). It's a 1–3 h build, so it's manual-trigger only.

## Using it in code
```cpp
int fourcc = cv::VideoWriter::fourcc('a','v','0','1');         // AV1 — royalty-free
cv::VideoWriter w("out.mkv", cv::CAP_FFMPEG, fourcc, 30.0, {1920,1080});
if (!w.isOpened()) { /* asked for a codec ffmpeg-free can't encode (H.264/mp4v) — by design */ }
```
RF FOURCCs: `av01` (AV1), `VP90`/`VP80` (VP9/8), `MJPG`. `avc1`/`mp4v` return `isOpened()==false`.

## GStreamer on Jetson — the real constraint
`gst-libav` (which gives GStreamer the `avenc_*`/`avdec_*` FFmpeg elements) links the **GStreamer
core**, so it must be built at your core's version — but old `gst-libav` won't compile against
**FFmpeg 8** (ffmpeg-free). Rough rule: FFmpeg 8 needs `gst-libav` ≳ **1.26**; JetPack 6.2 ships
GStreamer **1.20**, whose NVIDIA plugins (`nvv4l2decoder`, `nvarguscamerasrc`, …) are pinned to 1.20.
You can't have both NVIDIA's 1.20 plugins **and** a 1.26 ffmpeg-free `gst-libav` in one stack.

**Recommended Jetson architecture (no gst-libav needed):**
- **Input / HW decode / camera** → system GStreamer 1.20 (`CAP_GSTREAMER`, `nvv4l2decoder`, …).
  Decoding is the lower-risk side, and the HW blocks are where Jetson's value is.
- **Encode / output** → OpenCV `CAP_FFMPEG` → ffmpeg-free (software AV1/VP9/Opus). On **Orin Nano
  there is no hardware encoder at all**, so encode is software regardless.

This keeps everything royalty-free without fighting the version matrix. `build_gstreamer_ffmpeg_free.sh`
is for **generic Linux** (GStreamer ≥ 1.24/1.26, where you control the whole stack); on the JP6.2
combo it refuses to build a broken plugin unless `FORCE=1`.

## Stay royalty-free at runtime
- Don't install `gstreamer1.0-plugins-ugly` (that's `x264enc`/`x265enc`).
- Avoid HW H.264/H.265 encoder elements (`nvv4l2h264enc`, `nvv4l2h265enc`) — patent-encumbered.
- `OPENCV_ENABLE_NONFREE=OFF` is set — it enables the patented **SURF** in contrib (unrelated to codecs).
- Verify: `ldd $(your_binary) | grep avcodec` → `/opt/ffmpeg-free`, and
  `python3 -c "import cv2; print(cv2.getBuildInformation())" | grep -E 'FFMPEG|avcodec'`.

## Status / caveats
- These build scripts and the image are **v1** — they need on-device / CI validation (OpenCV+CUDA on
  Orin is a long build; expect a shake-out pass like the ffmpeg-free CI took).
- **OpenCV ≥ 4.13.0 is required** (the default). Earlier versions fail to *compile* against FFmpeg 8
  (ffmpeg-free) — they call `avcodec_close` / `av_stream_get_side_data`, removed in FFmpeg 7/8. 4.13.0
  added the version-guarded code paths (confirmed by CI shake-out: 4.11.0 errors in `cap_ffmpeg_impl.hpp`).
- LGPL: OpenCV links ffmpeg-free **dynamically** (`.so`) — compliant; ship the source offer (the
  `ffmpeg-*-source.tar.xz` on the ffmpeg-free Release) if you distribute binaries.
