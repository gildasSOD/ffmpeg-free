<p align="right">
  <a href="README.md"><img src="https://flagcdn.com/24x18/gb-eng.png" width="24" alt="English"> English</a>
  &nbsp;|&nbsp;
  <a href="README.ja.md"><img src="https://flagcdn.com/24x18/jp.png" width="24" alt="日本語"> 日本語</a>
</p>

# ロイヤリティフリー FFmpeg (`ffmpeg-free`)

**商用利用向けの、再頒布可能でロイヤリティフリーな [FFmpeg](https://ffmpeg.org) ビルド** — アップストリームの
ソースから、macOS（Apple Silicon）、Linux（x86-64 + NVIDIA CUDA、および arm64）、NVIDIA Jetson
（JetPack 6.2 / L4T r36）向けにビルドします。商用で FFmpeg を頒布する際につまずきやすい**2 つの軸**の両方を
クリーンに保つよう設計されています。すなわち、ソフトウェア著作権（GPL/AGPL/non-free の混入なし）**と**
コーデック特許ロイヤリティです。

> **固定アップストリーム:** FFmpeg **8.1.1 "Hoare"**（2026-05-04 リリース、最新安定系列）。[^ffver]

---

## 目次

1. [誰もが陥る誤解：独立した 2 つの法的な軸](#ja1)
2. [ここでの「ロイヤリティフリー」の意味 — そして意味しないこと](#ja2)
3. [軸 1 — ソフトウェア著作権（LGPL ビルド）](#ja3)
4. [軸 2 — コーデック特許とロイヤリティ](#ja4)
5. [コーデック契約（このビルドがエンコード/デコードできるもの）](#ja5)
6. [依存ライブラリのライセンス](#ja6)
7. [プラットフォームとハードウェアアクセラレーション](#ja7)
8. [自分でビルドする](#ja8)
9. [インストール](#ja9)
10. [LGPL コンプライアンス・チェックリスト（下流の利用者向け）](#ja10)
11. [参考文献](#references)

---

<a id="ja1"></a>
## 1. 独立した 2 つの法的な軸

「FFmpeg は商用利用できるのか？」という議論のほとんどは、**まったく別物の 2 つの法的問題**を混同しています。
両方をクリーンにする必要があります。

| | **軸 1 — ソフトウェア著作権** | **軸 2 — コーデック特許** |
|---|---|---|
| **対象** | FFmpeg 自身のコード + リンクするライブラリ | コーデックの*ビットストリーム/アルゴリズムそのもの* |
| **付与/留保するのは** | あなたが選ぶ `./configure` フラグ | 使用するコードに関係なく、特許プールや特許権者 |
| **失敗時の帰結** | 製品全体が GPL 化、または頒布不能になる | ユニット単位/ストリーム単位のロイヤリティ、または訴訟 |
| **解決策** | `--disable-gpl --disable-nonfree` + 動的リンク | *コーデック選択* — 特許で保護されたコーデックを**エンコードしない** |

落とし穴は **LGPL ≠ ロイヤリティフリー**であることです。FFmpeg の*ネイティブ*な H.264/H.265/AAC デコーダは
LGPL クリーン（軸 1 ✓）ですが、コーデック自体は依然として特許で保護されています（軸 2 ✗）。「LGPL」なビルド
でも、コーデックのロイヤリティを負う可能性があります。本プロジェクトは**両方の軸**を解決します。以下、出典付き
でその方法を示します。

> 「JPEG を読みたいだけ」というよくあるケースには朗報です。**JPEG の特許はすべて失効**しており（軸 2 ✓）、
> FFmpeg の `mjpeg` デコーダは LGPL（軸 1 ✓）です。JPEG の読み取りは明確に自由です。§4 参照。

---

<a id="ja2"></a>
## 2. ここでの「ロイヤリティフリー」の意味

このビルドは、**それを使って*生成・頒布*するものすべてが、コピーレフト義務とコーデック特許ロイヤリティの両方
から自由である**ように設計されています。

- **H.264、H.265/HEVC、AAC の*エンコーダ*を一切搭載しません**（ソフトウェアもハードウェアも）。したがって特許で
  保護されたメディアを**生成できません**。これはビルド時に強制され、検証可能です。`ffmpeg -encoders` にそれらは
  一切現れません（§5 参照）。
- エンコードできるのは**ロイヤリティフリー**なコーデックのみです：AV1、VP9/VP8、Opus、Vorbis、FLAC、
  MP3（特許失効済み）、MJPEG/JPEG、PNG、WebP、FFV1、ALAC。
- バイナリ自体は **LGPL-2.1+** であり、自由に再頒布できます（GPL なし、non-free なし）。

### 意味*しない*こと — 大規模に出荷する前に必ずお読みください

> **デコードは自動的にロイヤリティ免除にはなりません。** H.264、HEVC、AAC の特許ライセンスは、ロイヤリティ
> 対象の「ユニット」を*デコーダ、エンコーダ、またはその両方を含む製品*と定義しており、**デコード専用の除外
> 規定はありません**。[^avcunit][^aacfees] このビルドは入力互換性のために H.264/H.265/AAC を*デコードできます*が、
> その利便性には残存的な特許リスクが伴います。

実務上、このリスクは小さく管理可能です。理由は 2 つあります。

1. **無償/少量枠。** H.264 のプールは、法人ごとに**年間最初の 100,000 ユニットを $0.00** で許諾し（関連会社は
   1 つとして数える）、その後 1 ユニット $0.20、上限 年間 975 万ドルです。[^avcunit]
2. **ハードウェア/OS への委譲。** FFmpeg のソフトウェアデコーダではなくプラットフォームのハードウェア
   デコーダ（Apple VideoToolbox、NVIDIA NVDEC）でデコードする場合、コーデック特許ライセンスは通常
   **デバイス/OS ベンダー**側に乗り、あなたには及びません。[^nvenc-mit]

**証明可能なゼロ**の特許リスクが必要なら、**strict-RF プロファイル**（§5）をビルドしてください。これは特許
コーデックのデコーダを完全に除外します（代償として、世界で最も一般的なメディアを読めなくなります）。

> **ロイヤリティフリーなコーデックでさえ、残存的な*第三者*リスクを抱えています。**「ロイヤリティフリー」とは、
> 推進団体の拘束力ある許諾コミットメントと設計意図を反映したものであり、**外部の当事者が決して特許を主張しない
> という保証ではありません**。特筆すべき点：Sisvel は第三者特許に基づく AV1 および VP9 の商用ライセンス
> プログラムを運営しています。[^sisvel] **2026 年 3 月、Dolby は AV1 *および* HEVC をめぐって Snap を提訴**しました
> （係争中、AV1 ストリーミング実装者に対する初の大型訴訟）。[^dolby] また、第三者の「Opus Patent Pool」（Vectis、
> Dolby/Fraunhofer/NTT の特許を束ねる）が現在クレームを主張しています。[^opus-risk] 2026 年時点で**AV1 が有効かつ
> 必須の特許を侵害すると判断した裁判所はなく**、Sisvel が「必須」と指定した特許の一部は範囲を狭められたり無効化
> されたりしています。[^av1-litig] 当方は AV1 を最も有利な立場のコーデックと考えますが、リスクは率直に明記します。

---

<a id="ja3"></a>
## 3. 軸 1 — ソフトウェア著作権

FFmpeg のライセンスは `./configure` フラグによって完全に決まります。[^ffmpeg-license][^ffmpeg-legal]

| ビルド | ライセンス | 再頒布可能？ |
|---|---|---|
| **デフォルト**（`--enable-gpl` なし、`--enable-nonfree` なし） | **LGPL-2.1+** | ✅ 可（このビルド） |
| `--enable-gpl` | **GPL-2.0+**（バイナリ全体） | ✅ ただし GPL が伝播 |
| `--enable-nonfree` | non-free | ❌ **一切再頒布不可** |

- **デフォルト = LGPL-2.1+。**「FFmpeg のほとんどのファイルは GNU Lesser General Public License version 2.1 or
  later の下にある……組み合わせると FFmpeg には LGPL v2.1+ が適用される。」[^ffmpeg-license]
- **`--enable-gpl` は*バイナリ全体*を GPL にします。** GPL 専用ライブラリ（**`libx264`、`libx265`、`libxvid`**、
  `libvidstab`、`librubberband`、`frei0r` など）と、ツリー内の GPL フィルタ/アセンブリをリンクします。「それらの
  部分が使われると GPL が FFmpeg 全体に適用される。」[^ffmpeg-license][^ffmpeg-legal] 当方は**このフラグを決して
  渡しません**。だからこそ `libx264`/`libx265` の H.264/H.265 エンコーダを持たないのです。
- **`--enable-nonfree` は*再頒布不能*なバイナリを生成します。** GPL 非互換ライセンスのライブラリ
  — **Fraunhofer FDK-AAC** エンコーダ（`libfdk-aac`）、DeckLink、Fraunhofer MPEG-H デコーダ、そして
  — **当方にとって重要なことに** — NVIDIA の **NPP** および **`cuda-nvcc`/`cuda-sdk`** コンポーネント
  — を有効化します。[^configure-nonfree] 当方は**このフラグを決して渡しません**。

  > ⚠️ **CUDA の non-free の罠。**「NVIDIA サポートを充実させよう」として `--enable-libnpp` や
  > `--enable-cuda-nvcc` を加えるのはよくある誤りです。両方とも FFmpeg の*non-free* hwaccel リストに含まれる
  > ため、暗黙のうちに `--enable-nonfree` を強制し、バイナリを**法的に頒布不能**にします。[^configure-nonfree]
  > 当方は**無償**の方法で GPU アクセラレーションを得ます。すなわち MIT ライセンスの `ffnvcodec` ヘッダ +
  > LLVM/clang CUDA パス（`--enable-cuda-llvm`）です。NVENC/NVDEC と `av1_nvenc` は問題なく動作し、GPU は
  > ユーザがインストールした NVIDIA ドライバ経由で動きます（当方はドライバを同梱しません）。[^nvenc-mit]

- **`--enable-version3`** は LGPL-v3（GPL 部分があれば GPL-v3）に引き上げます。これは一部の Apache-2.0 /
  LGPLv3 ライブラリ（VMAF、mbedTLS、gmp など）にのみ必要です。[^ffmpeg-license] 当方の依存ライブラリはどれも
  必要としないため、ビルドはそのまま **LGPL-2.1+** を維持します。

当方のコーデックポリシーを*可能にする*重要な構造的事実：**FFmpeg にはネイティブ（組み込みソフトウェア）の
H.264/H.265 エンコーダが存在しません。** すべての H.264/H.265 エンコーダは、外部ライブラリ（`libx264`/`libx265`、
GPL；または Cisco の `libopenh264`）か*ハードウェア*エンコーダのいずれかです。一方、ネイティブの H.264/H.265
*デコーダ*は組み込みで LGPL です。[^allcodecs] つまり GPL ライブラリを有効化しないだけで、ソフトウェアの
H.264/H.265 エンコードは既に排除されます。当方はさらに*ハードウェア*エンコーダも無効化します（§5）。

---

<a id="ja4"></a>
## 4. 軸 2 — コーデック特許とロイヤリティ

状況は **2026 年 5 月**時点で調査したものです。特許ライセンスは頻繁に変わります。商用で何らかの数値に依拠する
前に、必ず一次情報を再確認してください。**本書は法的助言ではありません。**

### 特許で保護（当方は**デコード**のみ、**エンコード**しない）

| コーデック | プール/管理者（2026） | ロイヤリティ方式 | 頒布者への注記 |
|---|---|---|---|
| **H.264 / AVC** | **Via LA**（単一プール。2023 年に Via Licensing + MPEG LA から結成）[^avc-via] | 「ユニット」単位（デコーダ*または*エンコーダ）：**年間最初の 10 万は無償**、その後 $0.20、500 万超で $0.10；**上限 年 975 万ドル**。ストリーミングは別枠（2026 年以降の新規許諾者で最大 **年 450 万ドル**）。[^avcunit][^avcstream] | 最も「クリーン」なプールだが**ロイヤリティ有り**で、必須特許権者の*大半だが全部ではない*をカバー。[^avc-via] |
| **H.265 / HEVC** | **分断状態** — 歴史的に 3 プール（Via LA、**Access Advance**、Velos Media）+ 非プール権者[^hevc-frag] | ユニット単位；金額は非公開。2026 年 1 月から新規許諾者は **+25%**；料率は 2030 年まで固定。[^hevc-2030] | 主要コーデックで最もリスクが高い。2025 年 12 月、Access Advance が Via LA の HEVC/VVC プールを取得 — **統合は進行中だが単一ライセンスにはまだ至っていない**。[^hevc-consol] |
| **AAC** | **Via LA** AAC プール — **稼働中**（2026 年 3 月に HONOR が締結）[^aac-active] | 料金は**エンコーダ/デコーダの販売**に対して発生（$0.98 → $0.10/ユニット）；**AAC ビットストリームの頒布には発生しない**。[^aacfees] | コアの **AAC-LC** 米国特許は失効済みだが、**HE-AAC/xHE-AAC は失効しておらず**引き続き許諾対象。[^aaclc] → 当方は **AAC エンコーダを無効化**し、デコードのみとする。 |

> これらのプールはデコード専用利用を免除しないため、[^avcunit][^aacfees] *デコーダ*を大量に頒布する者は依然
> ロイヤリティを負う可能性があります — [§2](#ja2) の率直な注記を参照。

### ロイヤリティフリー（当方は**エンコード**も**デコード**も行う）

| コーデック | 「ロイヤリティフリー」の根拠 | 残存リスク |
|---|---|---|
| **AV1** | AOMedia Patent License 1.0 — AOMedia メンバーによる「無償・ロイヤリティフリー・取消不能」の許諾。エンコード+デコードを対象。[^aom-license] EU 反トラスト予備調査は **2023 年 5 月に措置なしで終結**。[^eu-aom] | **第三者**：Sisvel の AV1 プログラム；[^sisvel] **Dolby 対 Snap、2026 年 3 月（係争中）**。[^dolby] AV1 の侵害を認定した裁判所はない。[^av1-litig] |
| **VP9 / VP8** | Google による取消不能のロイヤリティフリー許諾；MPEG LA の VP8 プール構想は **2013 年に解消**され、Google が全 VP8 利用者にサブライセンス。[^vp8] | Sisvel の VP9 プログラム（Google は該当性を否定）。[^sisvel] |
| **Opus** | IETF **RFC 6716**；Xiph、Broadcom、Microsoft によるロイヤリティフリー特許許諾（防御的終了条項付き）。[^opus] | Vectis「Opus Patent Pool」；予防的 IPR 開示（Qualcomm/Huawei/Orange/Ericsson、Xiph 顧問は該当性を否定）。[^opus-risk] |
| **Vorbis, FLAC** | Xiph：「特許・ロイヤリティフリー」、既知の特許なし；参照ライブラリは BSD。[^flac][^vorbis] | 既知のものなし。 |
| **MP3** | **特許失効** — 最後のコア米国特許は 2017-04-16；Fraunhofer は 2017-04-23 に許諾終了（他国では約 2012 年）。[^mp3] `libmp3lame` は GPL ではなく **LGPL**。[^lame] | ベースライン MP3 には無し（Fraunhofer の「非コア」特許に関する軽微な留保）。[^mp3] |
| **JPEG**（ベースライン） | Forgent 特許（US 4,698,672）は無効化され **2006 年 10 月に失効**；委員会の目標はライセンス料不要のベースライン。[^jpeg] | *ベースライン* JPEG のみが対象 — JPEG 2000/XR/XL/XS は独自プールあり。[^jpeg] |
| **PNG** | ISO/IEC 15948 + W3C 勧告；既知の必須ロイヤリティ特許なし；`libpng` はパーミッシブ。[^png] | 既知のものなし。 |
| **WebP** | IETF **RFC 9649**（2024）；ロイヤリティフリー；`libwebp` は BSD（ロッシーモードはロイヤリティフリーの VP8 由来）。[^webp] | 既知のものなし。 |

---

<a id="ja5"></a>
## 5. コーデック契約

これはプロジェクト全体が依拠する、検証可能な約束です。**2 つのプロファイル**を生成します。

### プロファイル A — `decode-all`（デフォルト）
ほぼ何でも読み込み、ロイヤリティフリーなコーデックのみをエンコードします。

- **デコーダ：** FFmpeg ネイティブの全て（H.264、H.265、AAC、MP3、VP8/9、AV1、MJPEG/JPEG、ProRes、AC-3 など）
  + ハードウェアデコード。
- **エンコーダ：** **AV1**（`libsvtav1`、`libaom`）、**VP9/VP8**（`libvpx`）、**Opus**（`libopus`）、
  **Vorbis**（`libvorbis`）、**FLAC**、**ALAC**、**MP3**（`libmp3lame`）、**MJPEG/PNG/WebP**、**FFV1**。
- **除去したエンコーダ（強制）：** `h264_*`、`hevc_*`（全ハードウェア亜種）、および `aac`/`aac_at`/`aac_mf`。

### プロファイル B — `strict-rf`
特許リスクをゼロにするため、上記に加えて **H.264/H.265/AAC など*デコーダ*も除去**します。特許で保護された
メディアは読めません。コーデック特許との接触が一切ないことを証明する必要がある場合に使用します。

### 検証
すべてのリリースは CI で検査されます。任意のバイナリを自分でも検証できます。

```console
$ ffmpeg -hide_banner -version | grep -o -- '--enable-gpl\|--enable-nonfree' || echo "clean: LGPL, no nonfree"
clean: LGPL, no nonfree

$ ffmpeg -hide_banner -encoders | grep -iE '\b(h264|hevc|h265|aac)\b' || echo "no patent-codec encoders"
no patent-codec encoders
```

SHA で固定したソース tarball、正確な `./configure` 行、SBOM が各リリースに付属します。

---

<a id="ja6"></a>
## 6. 依存ライブラリのライセンス

リンクするすべてのライブラリはパーミッシブライセンスで、**いずれも GPL/AGPL ではありません**。したがって
FFmpeg バイナリを GPL 化しません。[^ffmpeg-license]（多くは明示的なロイヤリティフリー特許許諾も伴います
— 軸 1 への軸 2 の裏付けです。）

| ライブラリ | 役割 | SPDX ライセンス | 特許許諾 |
|---|---|---|---|
| **dav1d** | AV1 デコード | BSD-2-Clause[^dav1d] | — |
| **libaom** | AV1 エンコード/デコード（リファレンス） | BSD-2-Clause[^libaom] | AOM Patent License 1.0[^aom-license] |
| **SVT-AV1** | AV1 エンコード（高速） | BSD-3-Clause-Clear（≥v0.9）[^svtav1] | AOM Patent License 1.0[^svtav1] |
| **libvpx** | VP8 / VP9 | BSD-3-Clause[^libvpx] | Google ロイヤリティフリー許諾[^libvpx] |
| **libopus** | Opus | BSD-3-Clause[^libopus] | RF（Xiph/Broadcom/Microsoft）[^opus] |
| **libvorbis** | Vorbis | BSD-3-Clause[^libvorbis] | — |
| **libwebp** | WebP | BSD-3-Clause[^libwebp] | Google ロイヤリティフリー許諾[^libwebp] |
| **LAME**（`libmp3lame`） | MP3 エンコード | **LGPL**（GPL ではない）[^lame] | —（MP3 特許は失効済み） |
| **nv-codec-headers**（`ffnvcodec`） | NVENC/NVDEC API ヘッダ | **MIT**[^nvenc-mit] | —（GPU はユーザのドライバ経由） |

> **`libmp3lame` は GPL ではなく LGPL です** — 広く流布した誤解です。LAME の `COPYING` は「GNU *Library*
> GPL v2」（LGPL の旧称）であり、FFmpeg は*エンコーダ*としてのみリンクするため、LAME の GPL な `mpglib`
> デコーダは取り込まれません。[^lame]

---

<a id="ja7"></a>
## 7. プラットフォームとハードウェアアクセラレーション

HW アクセラレーションは**全プラットフォームでデコードに対して**有効です。HW **エンコード**はロイヤリティ
フリーなコーデックに限定します（そのため、シリコン上に存在する H.264/H.265 ハードウェアエンコーダはビルド時に
*無効化*します。§5）。

| プラットフォーム | フレームワーク | HW デコード | HW エンコード（RF のみ） |
|---|---|---|---|
| **macOS arm64**（Apple Silicon） | VideoToolbox | H.264、H.265、ProRes；**M3 以降で AV1**[^vt-av1] | 現状 RF は無し（Apple は M1/M2/M3 に **AV1 HW エンコーダを持たない**）[^vt-av1] |
| **Linux x86-64 + NVIDIA** | CUDA（LLVM）、NVDEC、NVENC、`ffnvcodec` | H.264、H.265、VP9；**Ampere 以降で AV1**[^nv-av1] | **Ada / RTX 40 シリーズ以降で `av1_nvenc`**[^nv-av1] |
| **Linux arm64**（汎用） | ソフトウェア（+ libva があれば VAAPI） | ソフトウェア | ソフトウェア |
| **NVIDIA Jetson**（JetPack 6.2） | V4L2 M2M / NVMPI[^jetson] | H.264、H.265、AV1、VP9（Orin） | **Orin Nano：無し**（HW エンコーダ自体が無い）[^orin-nano]；AGX Orin / Orin NX：H.264/H.265 → *ポリシーにより無効* |

注記：
- **Intel**（存在する場合）：`av1_qsv` / `av1_vaapi` が Arc 系 GPU でロイヤリティフリーな AV1 HW エンコードを
  提供します。[^intel-av1]
- **JetPack 6.2** = Jetson Linux **L4T 36.4.3**、Ubuntu 22.04 ルートファイルシステム、CUDA 12.6、
  **Orin ファミリーのみ**（Orin Nano/NX、AGX Orin）。[^jetpack] オリジナルの Maxwell 版「Jetson Nano」は
  **非対応**で、JetPack 4.x が上限です（**2024 年 11 月に EOL**）。[^jetson-eol] Jetson では HW コーデックは
  Tegra V4L2/NVMPI スタックを使い（デスクトップの NVENC/NVDEC ではない）、ツリー外の FFmpeg パッチが必要です。
  それらは主に当方が無効化する H.264/H.265 *エンコーダ*を追加するものなので、Jetson での HW の利点は
  **デコード**です。[^jetson]

### CI / ビルドランナー
- **macOS：** GitHub の Apple Silicon ランナー（`macos-14`/`macos-15`）、パブリックリポジトリは無料。[^gh-mac]
- **Linux x86-64：** `ubuntu-24.04`（CUDA ツールキットはジョブ内でインストール；GPU が無くてもバイナリは
  ビルド可能）。
- **Linux arm64 + Jetson：** GitHub の **arm64** ホストランナー（`ubuntu-24.04-arm`、2025 年 8 月 GA、
  パブリックは無料）。[^gh-arm] Jetson ジョブは NVIDIA の `nvcr.io/nvidia/l4t-jetpack:r36` コンテナ内で実行され、
  物理ボードは不要です。[^l4t-container]

---

<a id="ja8"></a>
## 8. 自分でビルドする

標準的な `./configure`（共通ベース。プラットフォーム別の追加は §7 と `CLAUDE.md` を参照）：

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

すべての依存ライブラリは再現性のために固定したソースからビルドします（ディストリのパッケージは使いません）。
完全なマルチプラットフォームパイプラインは `.github/workflows/` を参照してください。

---

<a id="ja9"></a>
## 9. インストール

**Ubuntu / Debian（GitHub Pages 上の APT リポジトリ）：**
```bash
curl -fsSL https://gildassod.github.io/ffmpeg-free/key.gpg | sudo tee /usr/share/keyrings/ffmpeg-free.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/ffmpeg-free.gpg] https://gildassod.github.io/ffmpeg-free stable main" \
  | sudo tee /etc/apt/sources.list.d/ffmpeg-free.list
sudo apt update && sudo apt install ffmpeg-free
```

**macOS（Homebrew tap）：**
```bash
brew tap gildasSOD/ffmpeg-free && brew install ffmpeg-free
```

**Docker：**
```bash
docker run --rm ghcr.io/gildassod/ffmpeg-free:latest -version
```

**tarball / 共有ライブラリ：** [Releases](https://github.com/gildasSOD/ffmpeg-free/releases) を参照。macOS の
tarball は未署名です。ブラウザでダウンロードした際に Gatekeeper が隔離した場合は
`xattr -dr com.apple.quarantine <dir>` で解除してください（Homebrew インストールは影響を受けません）。

---

<a id="ja10"></a>
## 10. LGPL コンプライアンス・チェックリスト

これらのライブラリを自分の製品に**組み込む**場合、LGPL の義務が依然として課されます（ここで配布するバイナリは
コンプライアンスを容易にするよう作られています）：[^ffmpeg-legal]

- [ ] `--enable-gpl` **なし**、`--enable-nonfree` **なし**でビルドする（対応済み — §5）。
- [ ] FFmpeg を**動的に**リンクする（静的ではなく共有 `.so`/`.dylib` を使い、利用者が再リンクできるようにする）。
- [ ] バイナリのビルドに使った**正確な FFmpeg ソース**を提供し、バイナリと同じ場所でホストする
      （本リリースには毎回同梱）。
- [ ] **LGPL-2.1 ライセンス本文**を同梱し、FFmpeg の著作権表示を保持する。
- [ ] ドキュメント/EULA 等に明記する：例「This software uses libraries from the FFmpeg project under the
      LGPLv2.1.」[^ffmpeg-legal]

> **免責事項。** 本書は 2026 年 5 月時点で公開されているライセンス情報を技術的指針としてまとめたものです。
> **法的助言ではありません。** 特許やライセンス条件は変わります。商用頒布の前に、資格を有する法律顧問の助言を
> 得てください。

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
