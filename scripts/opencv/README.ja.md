<p align="right">
  <a href="README.md"><img src="https://flagcdn.com/24x18/gb-eng.png" width="24" alt="English"> English</a>
  &nbsp;|&nbsp;
  <a href="README.ja.md"><img src="https://flagcdn.com/24x18/jp.png" width="24" alt="日本語"> 日本語</a>
</p>

# ロイヤリティフリー OpenCV（ffmpeg-free にリンク）

OpenCV の映像 I/O が、ディストリの GPL FFmpeg ではなく **[ffmpeg-free](../../README.ja.md)** を使うように
ビルドします。すると `cv::VideoWriter` は H.264/H.265/MPEG-4/AAC を**物理的に出力できなくなり**、ロイヤリティ
フリーなコーデック（AV1、VP9、Opus、MJPEG など）だけを出力します。これらのエンコーダがリンク先のライブラリに
含まれていないためです。

## なぜ素の OpenCV では不十分か
`apt install libopencv-dev` / `pip install opencv-python` は `libx264`/`libx265` でビルドされた **GPL**
FFmpeg をリンクするため、その `VideoWriter` は H.264 を生成*できて*しまい、特許/ロイヤリティのリスクが生じます。
解決策は、**OpenCV を ffmpeg-free に対して再ビルド**し、特許エンコーダをビルド依存から外すことです。

## ファイル
| ファイル | 用途 |
|---|---|
| `build_opencv.sh` | クリーンでパラメータ化された OpenCV+CUDA+contrib ビルド（ffmpeg-free にリンク。リンク先検証、Jetson/JetPack 6.2 の既定値付き）。 |
| `build_gstreamer_ffmpeg_free.sh` | GStreamer の `gst-libav`（avenc_*/avdec_*）を ffmpeg-free に対して再ビルド — 下記の Jetson の注意点を参照。 |
| `Dockerfile.jetson` | 再現可能なイメージ：`l4t-jetpack:r36` → ffmpeg-free → OpenCV（数時間のオンデバイスビルドを省略）。 |
| `../../.github/workflows/opencv-jetson.yml` | Jetson イメージをビルドして ghcr に公開する手動 CI。 |

## クイックスタート — Jetson（Orin / JetPack 6.2）で
```bash
# 1) ffmpeg-free（ロイヤリティフリーな FFmpeg）をインストール
curl -fsSL https://gildassod.github.io/ffmpeg-free/key.gpg | sudo tee /usr/share/keyrings/ffmpeg-free.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/ffmpeg-free.gpg] https://gildassod.github.io/ffmpeg-free stable main" \
  | sudo tee /etc/apt/sources.list.d/ffmpeg-free.list
sudo apt update && sudo apt install ffmpeg-free-jetson   # Jetson/L4T ビルド（arm64、JetPack 6.2）

# 2) それに対して OpenCV をビルド（ジョブ数は自動検出。8 GB Nano では zram/swap を足すと増やせる）
sudo ./build_opencv.sh                       # または: OPENCV_VERSION=4.13.0 JOBS=4 ./build_opencv.sh
```
スクリプトは `libopencv_videoio` が `/opt/ffmpeg-free/lib/libavcodec` をリンクしていることを検証し、誤って
ディストリの FFmpeg を拾った場合は失敗します。各種設定は環境変数です（`build_opencv.sh` のヘッダを参照）。

## ビルド済みイメージ（ビルドを省略）
```bash
docker run --rm --runtime nvidia ghcr.io/gildassod/opencv-free-jetson:latest \
  python3 -c "import cv2; print(cv2.getBuildInformation())"
```
自分で／CI でビルド：`docker buildx build -f scripts/opencv/Dockerfile.jetson .`、または **opencv-jetson**
ワークフローを実行（Actions → Run workflow）。1〜3 時間のビルドなので手動トリガー限定です。

## コードでの使い方
```cpp
int fourcc = cv::VideoWriter::fourcc('a','v','0','1');         // AV1 — ロイヤリティフリー
cv::VideoWriter w("out.mkv", cv::CAP_FFMPEG, fourcc, 30.0, {1920,1080});
if (!w.isOpened()) { /* ffmpeg-free がエンコードできないコーデック（H.264/mp4v）を要求した — 仕様どおり */ }
```
RF な FOURCC：`av01`（AV1）、`VP90`/`VP80`（VP9/8）、`MJPG`。`avc1`/`mp4v` は `isOpened()==false` を返します。

## Jetson での GStreamer — 本質的な制約
`gst-libav`（GStreamer に `avenc_*`/`avdec_*` の FFmpeg 要素を提供）は **GStreamer コア**をリンクするため、
コアと同じバージョンでビルドする必要があります。しかし古い `gst-libav` は **FFmpeg 8**（ffmpeg-free）に対して
コンパイルできません。目安：FFmpeg 8 には `gst-libav` ≳ **1.26** が必要。JetPack 6.2 は GStreamer **1.20** を
同梱しており、その NVIDIA プラグイン（`nvv4l2decoder`、`nvarguscamerasrc` など）は 1.20 に固定されています。
NVIDIA の 1.20 プラグイン**と** ffmpeg-free 用 1.26 の `gst-libav` を同一スタックに共存させることはできません。

**推奨される Jetson アーキテクチャ（gst-libav 不要）：**
- **入力 / HW デコード / カメラ** → システムの GStreamer 1.20（`CAP_GSTREAMER`、`nvv4l2decoder` など）。
  デコードはリスクの低い側であり、HW ブロックこそ Jetson の価値です。
- **エンコード / 出力** → OpenCV `CAP_FFMPEG` → ffmpeg-free（ソフトウェア AV1/VP9/Opus）。**Orin Nano には
  ハードウェアエンコーダが一切ない**ため、いずれにせよエンコードはソフトウェアです。

これでバージョンの組み合わせと格闘せずに全体をロイヤリティフリーに保てます。`build_gstreamer_ffmpeg_free.sh`
は**汎用 Linux**（GStreamer ≥ 1.24/1.26 で、スタック全体を自分で管理できる環境）向けです。JP6.2 の組み合わせ
では、`FORCE=1` を指定しない限り壊れたプラグインのビルドを拒否します。

## 実行時にロイヤリティフリーを維持する
- `gstreamer1.0-plugins-ugly` をインストールしない（`x264enc`/`x265enc` が入る）。
- HW の H.264/H.265 エンコーダ要素（`nvv4l2h264enc`、`nvv4l2h265enc`）を避ける — 特許で保護されている。
- `OPENCV_ENABLE_NONFREE=OFF` を設定済み — これは contrib の特許 **SURF** を有効化するもの（コーデックとは無関係）。
- 検証：`ldd $(your_binary) | grep avcodec` → `/opt/ffmpeg-free`、および
  `python3 -c "import cv2; print(cv2.getBuildInformation())" | grep -E 'FFMPEG|avcodec'`。

## ステータス / 注意点
- これらのビルドスクリプトとイメージは **v1** です — オンデバイス / CI での検証が必要です（Orin での
  OpenCV+CUDA は長いビルドで、ffmpeg-free の CI と同様にシェイクアウトが必要）。
- **OpenCV ≥ 4.13.0 が必須**（既定値）。これより古いバージョンは FFmpeg 8（ffmpeg-free）に対して*コンパイルに
  失敗*します — `avcodec_close` / `av_stream_get_side_data`（FFmpeg 7/8 で削除）を呼ぶためです。4.13.0 で
  バージョンガードされたコードパスが追加されました（CI シェイクアウトで確認：4.11.0 は `cap_ffmpeg_impl.hpp`
  でエラー）。
- LGPL：OpenCV は ffmpeg-free を**動的**（`.so`）にリンクします — 準拠。バイナリを配布する場合はソース提供
  （ffmpeg-free の Release にある `ffmpeg-*-source.tar.xz`）を添付してください。
