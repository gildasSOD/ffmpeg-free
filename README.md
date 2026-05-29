<p align="right">
  <a href="README.md"><img src="https://flagcdn.com/24x18/gb-eng.png" width="24" alt="English"> English</a>
  &nbsp;|&nbsp;
  <a href="README.ja.md"><img src="https://flagcdn.com/24x18/jp.png" width="24" alt="日本語"> 日本語</a>
</p>

# Royalty-Free FFmpeg (`ffmpeg-free`)

**Redistributable, royalty-free builds of [FFmpeg](https://ffmpeg.org) for commercial use** — built
from upstream source for macOS (Apple Silicon), Linux (x86-64 + NVIDIA CUDA, and arm64), and NVIDIA
Jetson (JetPack 6.2 / L4T r36). Engineered to be clean on **both** axes that trip up commercial FFmpeg
shipping: software copyright (no GPL/AGPL/non-free entanglements) **and** codec patent royalties.

> **Pinned upstream:** FFmpeg **8.1.1 "Hoare"** (released 2026-05-04, the latest stable series).[^ffver]

---

## Contents

1. [The one mistake everyone makes: two independent legal axes](#1-two-independent-legal-axes)
2. [What "royalty-free" means here — and what it does *not*](#2-what-royalty-free-means-here)
3. [Axis 1 — Software copyright (the LGPL build)](#3-axis-1--software-copyright)
4. [Axis 2 — Codec patents & royalties](#4-axis-2--codec-patents--royalties)
5. [The codec contract (what this build can encode / decode)](#5-the-codec-contract)
6. [Dependency licenses](#6-dependency-licenses)
7. [Platforms & hardware acceleration](#7-platforms--hardware-acceleration)
8. [Build it yourself](#8-build-it-yourself)
9. [Install](#9-install)
10. [LGPL compliance checklist (for downstream users)](#10-lgpl-compliance-checklist)
11. [References](#references)

---

## 1. Two independent legal axes

Almost every "is FFmpeg free for commercial use?" discussion conflates two **completely separate** legal
questions. You must be clean on **both**:

| | **Axis 1 — Software copyright** | **Axis 2 — Codec patents** |
|---|---|---|
| **Governs** | FFmpeg's own code + the libraries it links | The codec *bitstream / algorithm itself* |
| **Granted/withheld by** | the `./configure` flags you choose | patent pools & holders, regardless of which code you use |
| **Failure mode** | your whole product becomes GPL, or undistributable | per-unit / per-stream royalties or infringement suits |
| **Fixed by** | `--disable-gpl --disable-nonfree` + dynamic linking | *codec selection* — don't **encode** patent-encumbered formats |

The trap: **LGPL ≠ royalty-free.** FFmpeg's *native* H.264/H.265/AAC decoders are LGPL-clean (Axis 1 ✓)
yet the codecs themselves remain patent-encumbered (Axis 2 ✗). A build that is "LGPL" can still owe codec
royalties. This project closes **both** axes; the rest of this document shows exactly how, with sources.

> Good news for the common "I just need to read JPEGs" case: **JPEG's patents have all expired**
> (Axis 2 ✓) and FFmpeg's `mjpeg` decoder is LGPL (Axis 1 ✓) — reading JPEG is unambiguously free. See §4.

---

## 2. What "royalty-free" means here

This build is engineered so that **everything you *produce and distribute* with it is free of both
copyleft obligations and codec patent royalties:**

- It ships **no H.264, no H.265/HEVC, and no AAC *encoders*** of any kind (software *or* hardware) — so
  it **cannot generate** patent-encumbered media. This is enforced at build time and is auditable:
  `ffmpeg -encoders` lists none of them (see §5).
- It encodes only **royalty-free** codecs: AV1, VP9/VP8, Opus, Vorbis, FLAC, MP3 (patents expired),
  MJPEG/JPEG, PNG, WebP, FFV1, ALAC.
- The binary itself is **LGPL-2.1+** and freely redistributable (no GPL, no non-free).

### What it does *not* mean — read this before you ship at scale

> **Decoding is not automatically royalty-exempt.** The H.264, HEVC, and AAC patent licenses define a
> royalty-bearing "unit" as *a decoder, an encoder, or a product containing one of each* — there is **no
> decode-only carve-out**.[^avcunit][^aacfees] This build *can* decode H.264/H.265/AAC for input
> compatibility, and that convenience carries residual patent exposure.

In practice that exposure is small and manageable, for two reasons:

1. **Free / low-volume tiers.** H.264's pool charges **$0.00 for the first 100,000 units per year** per
   legal entity (affiliates counting as one), then $0.20/unit, capped at $9.75M/yr.[^avcunit]
2. **Hardware/OS delegation.** If you decode via the platform's hardware decoder (Apple VideoToolbox,
   NVIDIA NVDEC) instead of FFmpeg's software decoder, the codec patent license typically rides on the
   **device/OS vendor**, not on you.[^nvenc-mit]

If you need **provably zero** patent exposure, build the **strict-RF profile** (§5), which omits the
patent-codec decoders entirely — at the cost of being unable to read the world's most common media.

> **Even the royalty-free codecs carry residual *third-party* risk.** "Royalty-free" reflects the
> sponsoring bodies' binding licensing commitments and design intent — **not** a guarantee that no
> outside party will ever assert a patent. Notably: Sisvel runs commercial AV1 and VP9 licensing
> programs against third-party patents;[^sisvel] in **March 2026 Dolby sued Snap** over AV1 **and** HEVC
> (ongoing, the first major suit against an AV1 streaming implementer);[^dolby] and a third-party "Opus
> Patent Pool" (Vectis, bundling Dolby/Fraunhofer/NTT patents) is now asserting claims.[^opus-risk]
> As of 2026 **no court has ruled that AV1 infringes a valid, essential patent**, and several
> Sisvel-designated "essential" patents have been narrowed or invalidated.[^av1-litig] We consider AV1
> the best-positioned codec, but we state the risk plainly.

---

## 3. Axis 1 — Software copyright

FFmpeg's license is determined entirely by `./configure` flags.[^ffmpeg-license][^ffmpeg-legal]

| Build | License | Redistributable? |
|---|---|---|
| **default** (no `--enable-gpl`, no `--enable-nonfree`) | **LGPL-2.1+** | ✅ yes (this build) |
| `--enable-gpl` | **GPL-2.0+** (whole binary) | ✅ but virally GPL |
| `--enable-nonfree` | non-free | ❌ **not redistributable at all** |

- **Default = LGPL-2.1+.** "Most files in FFmpeg are under the GNU Lesser General Public License version
  2.1 or later… In combination the LGPL v2.1+ applies to FFmpeg."[^ffmpeg-license]
- **`--enable-gpl` makes the *entire* binary GPL.** It links GPL-only libraries — **`libx264`, `libx265`,
  `libxvid`**, `libvidstab`, `librubberband`, `frei0r`, and others — plus in-tree GPL filters/asm. "If
  those parts get used the GPL applies to all of FFmpeg."[^ffmpeg-license][^ffmpeg-legal] **We never pass
  this flag**, which is precisely why we have no `libx264`/`libx265` H.264/H.265 encoder.
- **`--enable-nonfree` produces an *unredistributable* binary.** It gates libraries whose licenses are
  GPL-incompatible — the **Fraunhofer FDK-AAC** encoder (`libfdk-aac`), DeckLink, the Fraunhofer MPEG-H
  decoder, and — **importantly for us** — NVIDIA's **NPP** and **`cuda-nvcc`/`cuda-sdk`** components.[^configure-nonfree]
  **We never pass this flag.**

  > ⚠️ **The CUDA non-free trap.** It is a common mistake to add `--enable-libnpp` or `--enable-cuda-nvcc`
  > for "better NVIDIA support." Both sit in FFmpeg's *non-free* hwaccel list, so they silently force
  > `--enable-nonfree` and make your binary **legally undistributable**.[^configure-nonfree] We get GPU
  > acceleration the **free** way instead: the MIT-licensed `ffnvcodec` headers + the LLVM/clang CUDA
  > path (`--enable-cuda-llvm`). NVENC/NVDEC and `av1_nvenc` work fine; the GPU runs via the user's
  > installed NVIDIA driver, which we never bundle.[^nvenc-mit]

- **`--enable-version3`** upgrades to LGPL-v3 (or GPL-v3 with GPL parts); needed only for a few Apache-2.0
  / LGPLv3 libraries (VMAF, mbedTLS, gmp…).[^ffmpeg-license] None of our dependencies require it, so the
  build stays plain **LGPL-2.1+**.

A key structural fact that makes our codec policy *possible*: **FFmpeg has no native (built-in software)
H.264 or H.265 encoder.** Every H.264/H.265 encoder is either an external library (`libx264`/`libx265`,
GPL; or Cisco's `libopenh264`) or a *hardware* encoder. The native H.264/H.265 *decoders*, by contrast,
**are** built in and LGPL.[^allcodecs] So simply *not* enabling GPL libraries already removes software
H.264/H.265 encoding — we only additionally disable the *hardware* ones (§5).

---

## 4. Axis 2 — Codec patents & royalties

Status as researched in **May 2026**. Patent licensing changes frequently — re-verify against the
primary sources before relying on any figure commercially. **This is not legal advice.**

### Patent-encumbered (we **decode** only, never **encode**)

| Codec | Pool / administrator (2026) | Royalty model | Notes for a distributor |
|---|---|---|---|
| **H.264 / AVC** | **Via LA** (single pool; formed 2023 from Via Licensing + MPEG LA)[^avc-via] | Per "unit" (decoder *or* encoder): **first 100k/yr free**, then $0.20, then $0.10 above 5M; **$9.75M/yr cap**. Streaming is separate (up to **$4.5M/yr** for new licensees from 2026).[^avcunit][^avcstream] | The "cleanest" pool, but **royalty-bearing**, and covers *most but not all* essential-patent holders.[^avc-via] |
| **H.265 / HEVC** | **Fragmented** — historically 3 pools (Via LA, **Access Advance**, Velos Media) + unpooled holders[^hevc-frag] | Per-unit; figures not public. **+25%** for new licensees from Jan 2026; rates locked through 2030.[^hevc-2030] | Riskiest mainstream codec. Dec 2025: Access Advance acquired Via LA's HEVC/VVC pools — **consolidating but not yet a single license**.[^hevc-consol] |
| **AAC** | **Via LA** AAC pool — **active** (HONOR signed Mar 2026)[^aac-active] | Fees due on **sale of encoders/decoders** ($0.98 → $0.10/unit); **none on distributing AAC bitstreams**.[^aacfees] | Core **AAC-LC** US patents have expired; **HE-AAC/xHE-AAC have not**, and remain licensed.[^aaclc] → we **disable the AAC encoder**; decode only. |

> Because these pools do not exempt decode-only use,[^avcunit][^aacfees] a high-volume distributor of the
> *decoders* may still owe royalties — see the honest scope note in [§2](#2-what-royalty-free-means-here).

### Royalty-free (we **encode** *and* decode)

| Codec | Basis for "royalty-free" | Residual risk |
|---|---|---|
| **AV1** | AOMedia Patent License 1.0 — "no-charge, royalty-free, irrevocable" grant from AOMedia members, covering encode + decode.[^aom-license] EU antitrust probe **closed May 2023, no action**.[^eu-aom] | **Third-party**: Sisvel AV1 program;[^sisvel] **Dolby v. Snap, Mar 2026 (ongoing)**.[^dolby] No court has found AV1 infringing.[^av1-litig] |
| **VP9 / VP8** | Google's irrevocable royalty-free grant; the MPEG LA VP8 pool effort was **dissolved in 2013** with Google sublicensing all VP8 users.[^vp8] | Sisvel VP9 program (Google disputes applicability).[^sisvel] |
| **Opus** | IETF **RFC 6716**; royalty-free patent grants from Xiph, Broadcom, Microsoft (defensive-termination).[^opus] | Vectis "Opus Patent Pool"; precautionary IPR disclosures (Qualcomm/Huawei/Orange/Ericsson) Xiph counsel disputes.[^opus-risk] |
| **Vorbis, FLAC** | Xiph: "patent-and-royalty-free", no known patents; BSD reference libs.[^flac][^vorbis] | None known. |
| **MP3** | **Patents expired** — last core US patent 2017-04-16; Fraunhofer ended licensing 2017-04-23 (≈2012 elsewhere).[^mp3] `libmp3lame` is **LGPL**, not GPL.[^lame] | None for baseline MP3 (minor Fraunhofer "non-core" caveat).[^mp3] |
| **JPEG** (baseline) | Forgent patent (US 4,698,672) invalidated & **expired Oct 2006**; committee goal is license-fee-free baseline.[^jpeg] | Scope to *baseline* JPEG only — **not** JPEG 2000/XR/XL/XS, which have their own pools.[^jpeg] |
| **PNG** | ISO/IEC 15948 + W3C Recommendation; no known essential royalty-bearing patents; `libpng` permissive.[^png] | None known. |
| **WebP** | IETF **RFC 9649** (2024); royalty-free; `libwebp` BSD (lossy mode derives from royalty-free VP8).[^webp] | None known. |

---

## 5. The codec contract

This is the auditable promise the whole project rests on. **Two profiles are produced:**

### Profile A — `decode-all` (default)
Reads virtually anything; encodes only royalty-free codecs.

- **Decoders:** all FFmpeg-native (H.264, H.265, AAC, MP3, VP8/9, AV1, MJPEG/JPEG, ProRes, AC-3, …) +
  hardware decode.
- **Encoders:** **AV1** (`libsvtav1`, `libaom`), **VP9/VP8** (`libvpx`), **Opus** (`libopus`),
  **Vorbis** (`libvorbis`), **FLAC**, **ALAC**, **MP3** (`libmp3lame`), **MJPEG/PNG/WebP**, **FFV1**.
- **Enforcement — allowlist:** built with `--disable-encoders --enable-encoder=<the codecs above + lossless/raw/PCM/text>`, so it *cannot* emit any other, encumbered codec — not only H.264/H.265/AAC but also MPEG-4 Part 2, MPEG-1/2, H.263, WMV/WMA, AC-3, ProRes.

### Profile B — `strict-rf`
For zero patent exposure: as above **but the H.264/H.265/AAC/etc. *decoders* are also removed.** Cannot
read patent-encumbered media. Use when you must be able to certify no codec-patent contact at all.

### Verification
Every release is checked in CI; you can verify any binary yourself:

```console
$ ffmpeg -hide_banner -version | grep -o -- '--enable-gpl\|--enable-nonfree' || echo "clean: LGPL, no nonfree"
clean: LGPL, no nonfree

$ ffmpeg -hide_banner -encoders | grep -iE '\b(h264|hevc|h265|aac)\b' || echo "no patent-codec encoders"
no patent-codec encoders
```

A SHA-pinned source tarball, the exact `./configure` line, and an SBOM ship with every release.

---

## 6. Dependency licenses

Every linked library is permissively licensed; **none is GPL/AGPL**, so none forces the FFmpeg binary to
GPL.[^ffmpeg-license] (Many also carry an explicit royalty-free patent grant — the Axis-2 belt to the
Axis-1 braces.)

| Library | Role | SPDX license | Patent grant |
|---|---|---|---|
| **dav1d** | AV1 decode | BSD-2-Clause[^dav1d] | — |
| **libaom** | AV1 encode/decode (reference) | BSD-2-Clause[^libaom] | AOM Patent License 1.0[^aom-license] |
| **SVT-AV1** | AV1 encode (fast) | BSD-3-Clause-Clear (≥v0.9)[^svtav1] | AOM Patent License 1.0[^svtav1] |
| **libvpx** | VP8 / VP9 | BSD-3-Clause[^libvpx] | Google royalty-free grant[^libvpx] |
| **libopus** | Opus | BSD-3-Clause[^libopus] | RF (Xiph/Broadcom/Microsoft)[^opus] |
| **libvorbis** | Vorbis | BSD-3-Clause[^libvorbis] | — |
| **libwebp** | WebP | BSD-3-Clause[^libwebp] | Google royalty-free grant[^libwebp] |
| **LAME** (`libmp3lame`) | MP3 encode | **LGPL** (not GPL)[^lame] | — (MP3 patents expired) |
| **nv-codec-headers** (`ffnvcodec`) | NVENC/NVDEC API headers | **MIT**[^nvenc-mit] | — (GPU via user's driver) |

> **`libmp3lame` is LGPL, not GPL** — a widely repeated error. LAME's `COPYING` is the "GNU *Library*
> GPL v2" (the LGPL's former name); FFmpeg links it only as an *encoder*, so LAME's GPL `mpglib` decoder
> is never pulled in.[^lame]

---

## 7. Platforms & hardware acceleration

HW acceleration is enabled for **decode everywhere**; HW **encode** is constrained to royalty-free codecs
(so the H.264/H.265 hardware encoders present on the silicon are *disabled at build time*, per §5).

| Platform | Frameworks | HW decode | HW encode (RF only) |
|---|---|---|---|
| **macOS arm64** (Apple Silicon) | VideoToolbox | H.264, H.265, ProRes; **AV1 on M3+**[^vt-av1] | none RF today (Apple has **no AV1 HW encoder** on M1/M2/M3)[^vt-av1] |
| **Linux x86-64 + NVIDIA** | CUDA (LLVM), NVDEC, NVENC, `ffnvcodec` | H.264, H.265, VP9; **AV1 on Ampere+**[^nv-av1] | **`av1_nvenc` on Ada / RTX 40-series+**[^nv-av1] |
| **Linux arm64** (generic) | software (+ VAAPI if present) | software | software |
| **NVIDIA Jetson** (JetPack 6.2) | V4L2 M2M / NVMPI[^jetson] | H.264, H.265, AV1, VP9 (Orin) | **Orin Nano: none** (no HW encoder at all)[^orin-nano]; AGX Orin / Orin NX: H.264/H.265 → *disabled by policy* |

Notes:
- **Intel** (where present): `av1_qsv` / `av1_vaapi` give royalty-free AV1 HW encode on Arc-class GPUs.[^intel-av1]
- **JetPack 6.2** = Jetson Linux **L4T 36.4.3**, Ubuntu 22.04 rootfs, CUDA 12.6, **Orin family only**
  (Orin Nano/NX, AGX Orin).[^jetpack] The original Maxwell "Jetson Nano" is **not** supported — it tops
  out at JetPack 4.x, which reached **end-of-life in Nov 2024**.[^jetson-eol] On Jetson, HW codecs use the
  Tegra V4L2/NVMPI stack (not desktop NVENC/NVDEC) and require out-of-tree FFmpeg patches; since those
  patches mainly add H.264/H.265 *encoders* we disable anyway, the HW value on Jetson is **decode**.[^jetson]

### CI / build runners
- **macOS:** GitHub Apple-Silicon runners (`macos-14`/`macos-15`), free for public repos.[^gh-mac]
- **Linux x86-64:** `ubuntu-24.04` (CUDA toolkit installed in-job; binaries build without a GPU present).
- **Linux arm64 + Jetson:** GitHub **arm64** hosted runners (`ubuntu-24.04-arm`, GA Aug 2025, free for
  public repos),[^gh-arm] with the Jetson job running inside NVIDIA's `nvcr.io/nvidia/l4t-jetpack:r36`
  container — no physical board required.[^l4t-container]

---

## 8. Build it yourself

The canonical `./configure` (common base; per-platform additions in §7 and `CLAUDE.md`):

```bash
./configure \
  --disable-gpl --disable-nonfree \          # Axis 1: stay LGPL & redistributable
  --enable-shared --disable-static \         # LGPL dynamic-linking compliance
  --enable-pic \
  --enable-libsvtav1 --enable-libaom --enable-libdav1d \
  --enable-libvpx --enable-libopus --enable-libvorbis \
  --enable-libwebp --enable-libmp3lame \
  --disable-encoders \
  --enable-encoder=libsvtav1,libaom_av1,libvpx,libvpx_vp9,libopus,libvorbis,flac,alac,\
libmp3lame,mjpeg,png,apng,gif,libwebp,libwebp_anim,ffv1,wavpack,pcm_s16le,rawvideo \
  --disable-ffplay --disable-doc          # build ffmpeg + ffprobe (default); skip ffplay (needs SDL)
```

All dependencies are built from pinned source (not distro packages) for reproducibility. See
`.github/workflows/` for the full multi-platform pipeline.

---

## 9. Install

**Ubuntu / Debian (APT repo on GitHub Pages):**
```bash
curl -fsSL https://gildassod.github.io/ffmpeg-free/key.gpg | sudo tee /usr/share/keyrings/ffmpeg-free.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/ffmpeg-free.gpg] https://gildassod.github.io/ffmpeg-free stable main" \
  | sudo tee /etc/apt/sources.list.d/ffmpeg-free.list
sudo apt update && sudo apt install ffmpeg-free
```

**macOS (Homebrew tap):**
```bash
brew tap gildasSOD/ffmpeg-free && brew install ffmpeg-free
```

**Docker:**
```bash
docker run --rm ghcr.io/gildassod/ffmpeg-free:latest -version
```

**Tarballs / shared libs:** see [Releases](https://github.com/gildasSOD/ffmpeg-free/releases). macOS
tarballs are unsigned — if Gatekeeper quarantines a browser download, clear it with
`xattr -dr com.apple.quarantine <dir>`. (Homebrew installs are not affected.)

---

## 10. LGPL compliance checklist

If you **embed** these libraries in your own product, the LGPL still imposes obligations (the binaries
here are built to make compliance easy):[^ffmpeg-legal]

- [ ] Build **without** `--enable-gpl` and **without** `--enable-nonfree` (done — see §5).
- [ ] Link FFmpeg **dynamically** (use the shared `.so`/`.dylib`, not static), so users can relink.
- [ ] **Provide the exact FFmpeg source** your binaries were built from, hosted alongside them (shipped
      with every release here).
- [ ] Include the **LGPL-2.1 license text** and retain FFmpeg's copyright notices.
- [ ] State, e.g. in your docs/EULA: *"This software uses libraries from the FFmpeg project under the
      LGPLv2.1."*[^ffmpeg-legal]

> **Disclaimer.** This document summarizes publicly available licensing information as of May 2026 for
> engineering guidance. It is **not legal advice**. Patent and license terms change; obtain advice from
> qualified counsel before commercial distribution.

---

## References

<!-- Software license / FFmpeg mechanics -->
[^ffver]: FFmpeg — Download (8.1.1 "Hoare", 2026-05-04). https://ffmpeg.org/download.html
[^ffmpeg-license]: FFmpeg — `LICENSE.md` (master). https://github.com/FFmpeg/FFmpeg/blob/master/LICENSE.md
[^ffmpeg-legal]: FFmpeg — License and Legal Considerations (LGPL compliance checklist). https://ffmpeg.org/legal.html
[^configure-nonfree]: FFmpeg — `configure` (master): `EXTERNAL_LIBRARY_NONFREE_LIST` = decklink, libfdk_aac, libmpeghdec; `HWACCEL_LIBRARY_NONFREE_LIST` = libnpp, cuda_nvcc, cuda_sdk. https://github.com/FFmpeg/FFmpeg/blob/master/configure  · libfdk-aac note: https://ffmpeg.org/general.html
[^allcodecs]: FFmpeg — `libavcodec/allcodecs.c` (master): no `ff_h264_encoder`/`ff_hevc_encoder`; native `ff_h264_decoder`/`ff_hevc_decoder` present. https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/allcodecs.c
[^nvenc-mit]: FFmpeg — `nv-codec-headers` (MIT); FFmpeg General Docs: "The NVENC library… header file is licensed under the compatible MIT license, requires a proprietary binary blob at run time." https://github.com/FFmpeg/nv-codec-headers · https://ffmpeg.org/general.html

<!-- Video codec patents -->
[^avc-via]: Via Licensing Alliance — AVC/H.264 program (Via LA formed 2023 from Via Licensing + MPEG LA). https://www.via-la.com/licensing-programs/avc-h-264/ · https://www.via-la.com/via-licensing-and-mpeg-la/
[^avcunit]: Via LA — AVC/H.264 rates: a "unit" = decoder, encoder, or one of each; first 100,000 units/yr = $0.00; then $0.20; $0.10 above 5M; $9.75M/yr enterprise cap. https://www.via-la.com/licensing-programs/avc-h-264/ · briefing PDF: https://via-la.com/wp-content/uploads/2025/09/avcweb.pdf
[^avcstream]: AVC streaming fees raised to up to $4.5M/yr for new licensees from 2026 (replacing flat $100k cap). https://www.streamingmedia.com/Articles/ReadArticle.aspx?ArticleID=173935 · https://www.tomshardware.com/service-providers/streaming/h264-streaming-license-fees-jump-from-100000-to-4-5-million
[^hevc-frag]: HEVC's multi-pool + unpooled fragmentation (Via LA / Access Advance / Velos Media). https://streaminglearningcenter.com/codecs/hevc-licensing-misunderstood-maligned-and-surprisingly-successful.html
[^hevc-consol]: Access Advance acquires Via LA's HEVC/VVC pools (eff. Dec 15, 2025; single combined pool a stated future goal). https://ipfray.com/breaking-access-advance-acquires-via-licensing-alliances-hevc-vvc-patent-pools/
[^hevc-2030]: Access Advance — HEVC/VVC pricing through 2030 (+25% for new licensees from Jan 2026). https://accessadvance.com/2025/07/21/access-advance-announces-hevc-advance-and-vvc-advance-pricing-through-2030/
[^aom-license]: Alliance for Open Media — Patent License 1.0 ("no-charge, royalty-free, irrevocable"). https://aomedia.org/license/patent-license/
[^eu-aom]: European Commission ends preliminary antitrust investigation of AOMedia RF licensing (closed 2023-05-23, no action). https://www.clearygottlieb.com/news-and-insights/news-listing/european-commission-ends-preliminary-antitrust-investigation-of-aomedia-royalty-free-licensing-policy-for-seps
[^sisvel]: Sisvel — Video Coding Platform (AV1 & VP9 third-party licensing programs). https://www.sisvel.com/licensing-programmes/audio-and-video-coding-decoding/video-coding-platform-av1/
[^dolby]: Dolby v. Snap (filed 2026-03-23; AV1 + HEVC; US D. Del. 1:26-cv-00317 + Rio de Janeiro), ongoing. https://ipfray.com/dolby-sues-snapchat-over-av1-and-hevc-patent-infringement-in-u-s-and-brazil-access-advance-vdp-license-would-resolve-issue/
[^av1-litig]: Unified Patents — AV1 patent-validity outcomes (several Sisvel-designated patents narrowed/invalidated; no AV1 infringement ruling). https://www.unifiedpatents.com/insights/tag/AV1
[^vp8]: Google & MPEG LA agreement, 2013-03-07 — MPEG LA "discontinue[s] its effort to form a VP8 patent pool"; Google may sublicense all VP8 users. https://www.businesswire.com/news/home/20130307006192/en/Google-MPEG-LA-Announce-Agreement-Covering-VP8 · WebM FAQ: https://www.webmproject.org/about/faq/

<!-- Audio / image codec patents -->
[^aac-active]: Via LA — AAC pool active in 2026 (HONOR new licensee, 2026-03-09). https://www.via-la.com/via-licensing-alliance-welcomes-honor-as-advanced-audio-coding-patent-pool-licensee/
[^aacfees]: Via LA — AAC fees due "on the sale of encoders and/or decoders only… no patent license fees due for the distribution of bit-streams." https://www.via-la.com/licensing-programs/aac/
[^aaclc]: AAC-LC core US patents expired; higher profiles (HE-AAC/SBR, xHE-AAC) not — Fedora ships AAC-LC-only "fdk-aac-free". https://en.wikipedia.org/wiki/Fraunhofer_FDK_AAC · https://fedoraproject.org/wiki/Licensing/FDK-AAC
[^mp3]: MP3 patents expired (last core US patent 2017-04-16; program ended 2017-04-23). https://www.audioblog.iis.fraunhofer.com/mp3-software-patents-licenses · https://en.wikipedia.org/wiki/MP3
[^opus]: Opus — IETF RFC 6716; royalty-free patent grants. https://www.rfc-editor.org/info/rfc6716/ · https://opus-codec.org/license/
[^opus-risk]: Opus residual risk — Vectis "Opus Patent Pool"; precautionary IETF IPR disclosures. https://en.wikipedia.org/wiki/Opus_(audio_format) · https://www.opuspool.com/
[^flac]: FLAC — License (no royalties, no known patents; New BSD libs). https://xiph.org/flac/license.html
[^vorbis]: Vorbis — Xiph ("patent-and-royalty-free"). https://xiph.org/vorbis/
[^jpeg]: JPEG — Forgent patent US 4,698,672 invalidated/expired 2006; baseline royalty-free (scope: baseline JPEG only). https://en.wikipedia.org/wiki/JPEG · https://jpeg.org/terms.html
[^png]: PNG — W3C Recommendation / ISO-IEC 15948; no known essential royalty-bearing patents. https://www.w3.org/TR/png-3/
[^webp]: WebP — IETF RFC 9649 (2024); libwebp BSD. https://en.wikipedia.org/wiki/WebP · https://chromium.googlesource.com/webm/libwebp

<!-- Dependency licenses -->
[^dav1d]: dav1d — `COPYING` (BSD-2-Clause). https://code.videolan.org/videolan/dav1d/-/blob/master/COPYING
[^libaom]: libaom — `LICENSE` (BSD-2-Clause) + `PATENTS` (AOM Patent License 1.0). https://aomedia.googlesource.com/aom/+/refs/heads/main/LICENSE
[^svtav1]: SVT-AV1 — `LICENSE.md` (BSD-3-Clause-Clear since v0.9) + `PATENTS.md` (AOM Patent License 1.0). https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/LICENSE.md
[^libvpx]: libvpx — `LICENSE` (BSD-3-Clause) + `PATENTS` (Google RF grant). https://github.com/webmproject/libvpx/blob/main/LICENSE
[^libopus]: libopus — `COPYING` (BSD-3-Clause). https://github.com/xiph/opus/blob/master/COPYING
[^libvorbis]: libvorbis — `COPYING` (BSD-3-Clause). https://github.com/xiph/vorbis/blob/master/COPYING
[^libwebp]: libwebp — `COPYING` (BSD-3-Clause) + `PATENTS` (Google RF grant). https://github.com/webmproject/libwebp/blob/main/COPYING
[^lame]: LAME — `license.txt` (LGPL; "link as separate library"; mpglib *decoder* is GPL, not linked by FFmpeg). https://lame.sourceforge.io/license.txt

<!-- Platforms / hardware -->
[^vt-av1]: Apple VideoToolbox — AV1 HW *decode* on M3+/A17 Pro; no AV1 HW *encode* on M1/M2/M3. https://developer.apple.com/forums/thread/722933 · https://developer.apple.com/documentation/videotoolbox
[^nv-av1]: NVIDIA — AV1 NVENC encode requires Ada Lovelace (RTX 40-series+); AV1 NVDEC decode from Ampere+. https://developer.nvidia.com/blog/improving-video-quality-and-performance-with-av1-and-nvidia-ada-lovelace-architecture/ · https://developer.nvidia.com/video-encode-and-decode-support-matrix
[^orin-nano]: NVIDIA Developer Forums — "No hardware encoders in Orin Nano" (SW encode only; AGX Orin / Orin NX have HW encode). https://forums.developer.nvidia.com/t/av1-encoding-on-jetson-orin-nano/276038
[^intel-av1]: FFmpeg — Intel QSV / VAAPI AV1 encode (`av1_qsv`, `av1_vaapi`). https://trac.ffmpeg.org/wiki/Hardware/QuickSync · https://trac.ffmpeg.org/wiki/Hardware/VAAPI
[^jetpack]: NVIDIA — JetPack SDK 6.2 (Jetson Linux 36.4.3, Ubuntu 22.04, CUDA 12.6; Orin family). https://developer.nvidia.com/embedded/jetpack-sdk-62
[^jetson]: Jetson HW codecs via Tegra V4L2 M2M / NVMPI; out-of-tree FFmpeg patches (e.g. jocover/jetson-ffmpeg). https://github.com/jocover/jetson-ffmpeg
[^jetson-eol]: NVIDIA — End of Life for JetPack 4 (final 4.6.6 / L4T 32.7.6; EOL Nov 2024) — original Maxwell Jetson Nano is JetPack 4.x only. https://forums.developer.nvidia.com/t/announcing-end-of-life-for-nvidia-jetpack-4-with-the-release-of-jetpack-4-6-6/314300
[^l4t-container]: NVIDIA NGC — `l4t-jetpack` container (r36 tags). https://catalog.ngc.nvidia.com/orgs/nvidia/containers/l4t-jetpack
[^gh-arm]: GitHub — arm64 hosted runners GA for public repos (2025-08-07; `ubuntu-24.04-arm`). https://github.blog/changelog/2025-08-07-arm64-hosted-runners-for-public-repositories-are-now-generally-available/
[^gh-mac]: GitHub — Apple-Silicon macOS runners (`macos-14`/`macos-15`), free for public repos. https://docs.github.com/en/actions/reference/runners/github-hosted-runners
