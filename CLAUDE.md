# ffmpeg-free — royalty-free FFmpeg builds

> Public GitHub repo: **`gildasSOD/ffmpeg-free`** (personal account, public). The name reflects the real
> differentiator — *royalty-free*, not merely LGPL.

## 1. What this project is

Produce **redistributable, royalty-free** FFmpeg binaries and shared libraries, built from
upstream FFmpeg source, for commercial use across macOS, Linux and NVIDIA Jetson — free of
**both** copyleft-copyright entanglements (GPL/AGPL/nonfree) **and** codec **patent royalties**
for anything we distribute or encode. The build aims to stay *almost* as capable as a stock
"kitchen-sink" FFmpeg: it can **read/decode practically anything**, and **encode** only with
codecs that carry no patent royalties.

The downstream consumer of record is the `smart-streamer` project (per its ADR-0003, "Ship and
depend on the LGPL build of FFmpeg"), but this repo is a **standalone, general-purpose distribution**.

## 2. Core principle — two INDEPENDENT legal axes

The most common mistake (and the one our README must debunk) is treating "LGPL build" as
"free build". They are different things:

| Axis | What it governs | How we satisfy it |
|------|-----------------|-------------------|
| **Software copyright license** | FFmpeg's own code + the libraries it links | `--disable-gpl --disable-nonfree`, dynamic linking, ship source + LGPL text |
| **Codec patents / royalties** | The *bitstream/algorithm itself*, regardless of which code implements it | Codec policy in §3 — never **encode** a patent-encumbered codec |

**LGPL ≠ royalty-free.** FFmpeg's native decoders for H.264/H.265/AAC are LGPL-clean yet the
codecs remain patent-encumbered. A "free FFmpeg" must be clean on **both** axes.

Useful fact for our specific use case: **JPEG patents have all expired**, so reading JPEG via
FFmpeg's native `mjpeg`/`jpeg` decoder is royalty-free with no caveats.

## 3. Codec policy (the contract — enforced at `./configure` time)

**DECODE — permissive (reading input; *not* royalty-exempt — see caveat):**
- Everything FFmpeg-native supports: H.264, H.265/HEVC, MPEG-2/4, VP8/VP9, AV1, **MJPEG/JPEG**,
  ProRes, AAC, MP3, AC-3, etc. Plus HW-accelerated decode (see §4).
- ⚠️ **Caveat:** the H.264/HEVC/AAC patent pools license a "unit" as *a decoder, an encoder, or both* —
  there is **no decode-only exemption**. Residual decode-side exposure is mitigated by free/low-volume
  tiers (H.264: first 100k units/yr per legal entity free) and by delegating decode to the OS/hardware
  decoder (VideoToolbox, NVDEC), whose patent licence rides on the device. Downstream users who need
  *provably zero* patent exposure should use the **strict-RF profile** (no patent-codec decoders). The
  README documents this honestly — we do not claim the decode-all build is "100% royalty-free".

**ENCODE — royalty-free codecs ONLY:**
- Video: **AV1** (`libsvtav1` for speed, `libaom-av1` for reference quality; `libdav1d` for decode),
  **VP9/VP8** (`libvpx`), lossless **FFV1** (FFmpeg-native, royalty-free).
- Audio: **Opus** (`libopus`), **Vorbis** (`libvorbis`), **FLAC** (native), **MP3** (`libmp3lame`
  — LAME is LGPL-compatible *and* MP3 patents expired in 2017), **ALAC** (royalty-free).
- Image: **MJPEG/JPEG** (native — patents expired), **PNG** (native), **WebP** (`libwebp`).

**NEVER (hard rules):**
- `--enable-gpl` → would pull `libx264`, `libx265`, `libxvid`, GPL filters. Forbidden.
- `--enable-nonfree` → would pull `libfdk-aac` (non-redistributable). Forbidden.
- **Encoder ALLOWLIST, not a denylist.** FFmpeg ships native encoders for many *encumbered* codecs
  (MPEG-4 Part 2, MPEG-1/2, H.263, WMV/WMA, AC-3, ProRes) plus HW H.264/H.265 (nvenc/vaapi/vulkan/qsv/…).
  A denylist always misses some, so we build `--disable-encoders --enable-encoder=<RF set>`: AV1
  (libsvtav1/libaom), VP8/9 (libvpx), Opus, Vorbis, FLAC, ALAC, MP3 (libmp3lame), MJPEG, PNG, GIF, WebP,
  FFV1 + lossless/raw/PCM + text subtitles. Everything else — including **AAC** — cannot be produced.

**Auditability:** after build, `ffmpeg -encoders` lists **only** royalty-free encoders (no H.264/H.265,
AAC, MPEG-4/2, WMV, AC-3, ProRes…). The build's `audit()` asserts this and fails otherwise — the provable
claim the README rests on (and the runtime self-check, §7).

## 4. Hardware acceleration

Enabled — but **for decode + royalty-free encode only**, per §3.

| Platform | Frameworks enabled | HW decode | HW encode (RF only) |
|----------|--------------------|-----------|---------------------|
| macOS arm64 (Apple Silicon) | VideoToolbox | H.264/H.265/ProRes/AV1* | (none RF on Apple silicon today) |
| Linux amd64 + NVIDIA | CUDA (LLVM), NVDEC, NVENC (`ffnvcodec`, MIT) | H.264/H.265/AV1/VP9 | `av1_nvenc` where the GPU supports it (Ada/RTX 40+) |
| Linux arm64 (generic) | software (+ VAAPI if present) | software | software |
| Jetson Orin / JetPack 6.2 (L4T 36.4.3) | V4L2 M2M / NVMPI | H.264/H.265/AV1/VP9 | **Orin Nano: none** (no HW encoder — SW encode only); AGX Orin / Orin NX: H.264/H.265 (disabled by policy) |

\* AV1 HW **decode** on M3 and newer. HW H.264/H.265 **encoders** are present on this silicon
but are **disabled at configure time** by policy (§3).

## 5. Build configuration (canonical flags)

Common base (all platforms):
```
--prefix=<staged>
--disable-gpl --disable-nonfree          # copyright axis
--enable-shared --disable-static         # LGPL dynamic-linking compliance (stays LGPL-2.1+)
--enable-pic
--enable-libsvtav1 --enable-libaom --enable-libdav1d \
--enable-libvpx --enable-libopus --enable-libvorbis \
--enable-libwebp --enable-libmp3lame
--disable-encoders \
--enable-encoder=libsvtav1,libaom_av1,libvpx,libvpx_vp9,libopus,libvorbis,flac,alac,\
libmp3lame,mjpeg,png,apng,gif,libwebp,libwebp_anim,ffv1,wavpack,pcm_s16le,rawvideo
--disable-ffplay --disable-doc           # ffmpeg+ffprobe build by default; skip ffplay (SDL)
```
Per-platform adds:
- **macOS:** `--enable-videotoolbox`.
- **Linux + NVIDIA:** `--enable-ffnvcodec --enable-cuda-llvm --enable-cuvid --enable-nvdec --enable-nvenc`.
  ⚠️ **Do NOT use `--enable-libnpp`, `--enable-cuda-nvcc`, or `--enable-cuda-sdk`** — FFmpeg's `configure`
  places all three in its *nonfree* hwaccel list, so they force `--enable-nonfree` and make the binary
  **unredistributable**. Use the LLVM/clang CUDA path (`--enable-cuda-llvm`) and the MIT `ffnvcodec`
  headers instead; HW decode and `av1_nvenc` (royalty-free) still work — the GPU runs via the user's driver.
- **Jetson (L4T r36):** `--enable-v4l2-m2m` + out-of-tree NVMPI patches (e.g. `jocover/jetson-ffmpeg`).
  Those patches mostly add H.264/HEVC *encoders*, which our policy disables anyway — on Jetson the HW win is **decode**.

**Licensing note:** all external *codec* libs above are BSD/MIT/LGPL — none trip the GPL axis. The NVIDIA
NPP / `cuda-nvcc` components are the *nonfree* trap to avoid (above), independent of the GPL question.

- **FFmpeg version:** pin **8.1.1 "Hoare"** (2026-05-04, latest stable); bump deliberately. Reproducible
  builds. Note `libpostproc` was removed in FFmpeg 8.0, so it is no longer a built-in GPL component.
- Build each dependency from pinned source too (don't trust distro packages for the codec libs).

## 6. Platform / CI matrix

| Target | Runner | Notes |
|--------|--------|-------|
| macOS arm64 | GitHub `macos-14`+ (Apple Silicon) | VideoToolbox; Homebrew only for build deps, not for FFmpeg itself |
| Linux amd64 + CUDA | GitHub `ubuntu-24.04` | CUDA toolkit installed in-job; builds CUDA binaries even without a GPU present (no runtime GPU test in CI) |
| Linux arm64 | GitHub `ubuntu-24.04-arm` (free for public repos) | generic aarch64 |
| Jetson / JetPack 6.2 | `ubuntu-24.04-arm` running **`nvcr.io/nvidia/l4t-jetpack:r36.x`** container | L4T r36 (Ubuntu 22.04 base, CUDA 12.x); no physical device needed. **Orin Nano** — the Maxwell "Jetson Nano" cannot run JetPack 6.2 |

## 7. Distribution & compliance

Artifacts produced by CI, per platform:
1. **CLI** — `ffmpeg` + `ffprobe` (tarball).
2. **Shared libs + headers** — `libav*` `.dylib`/`.so` + dev headers (for LGPL dynamic linking).
3. **Docker images** — per-arch OCI (amd64, arm64, L4T/Jetson); matches the smart-streamer ADR.
4. **OS packages** — `ffmpeg-free` `.deb` (Ubuntu 24.04) + a Homebrew tap (macOS). macOS CLI tarballs
   ship **unsigned** (no codesign/notarization); `brew` install clears the Gatekeeper quarantine, direct
   downloads may need `xattr -dr com.apple.quarantine`.
5. **Public APT repo on GitHub Pages** — signed `dists/`+`pool/` so users run
   `apt install ffmpeg-free` after adding the repo. Needs a **GPG signing key** (CI secret).

**LGPL compliance, shipped with every release:**
- the **exact FFmpeg source** used + the `./configure` line + any patches,
- the **LGPL-2.1 / LGPL-3.0 license texts** and third-party copyright notices,
- SBOM listing every linked library and its license.

**Runtime self-check** (carried over from the ADR): on first run, log `ffmpeg -version`'s
configuration line; assert it contains neither `--enable-gpl` nor `--enable-nonfree`, and that
`ffmpeg -encoders` exposes no H.264/H.265/AAC encoder.

## 8. Repo & identity

- **GitHub:** account **`gildasSOD`** (`gildas.tuffin@smaopi.com`) — personal account, **not** the
  `Smart-Opinion-Dev` organization. Repository is **public**.
- **Commits:** authored `gildasSOD <gildas.tuffin@smaopi.com>`. **No `Co-Authored-By: Claude`
  trailer** (consistent with the user's standing preference).
- **License of this repo's own scripts/CI:** **MIT** (see `LICENSE`) — FFmpeg artifacts themselves
  remain LGPL-2.1+. The repo holds only build scripts/CI/docs; it ships no FFmpeg source in-tree.

## 9. Deliverables

- [x] `CLAUDE.md` — this contract.
- [x] `README.md` — public, professional, cited licensing/patent explainer.
- [x] `.github/workflows/` — build matrix (§6) + signed APT-repo publish (§7).
- [x] `scripts/` — portable build script + pinned dependency manifest (`versions.env`).
- [x] `LICENSE` (MIT). SBOM + third-party notices generated per-release by CI (pending first run).

## 10. Open items / assumptions (correct me)

Resolved 2026-05-29:
- **Name:** `ffmpeg-free`. ✅
- **FFmpeg version:** 8.1.1 (latest stable). ✅
- **Repo's own license:** MIT. ✅
- **macOS:** unsigned tarballs + Homebrew tap (no notarization). ✅
- **`.deb` / `apt install` name:** `ffmpeg-free`. ✅
- **APT repo:** GitHub Pages, signed with a dedicated GPG key in the `APT_GPG_PRIVATE_KEY` repo secret. ✅

Still to verify at the first CI run: the exact pinned dependency versions in `scripts/versions.env`, and the
live `nvcr.io/nvidia/l4t-jetpack` r36 tag (r36.4.3 has been intermittently absent from NGC — pin r36.4.0 or
pass the tag as a workflow input).
