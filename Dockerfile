# syntax=docker/dockerfile:1
#
# Royalty-free FFmpeg image. Default build uses portable software codecs (works on
# linux/amd64 and linux/arm64). For NVIDIA CUDA acceleration set BASE to an
# nvidia/cuda runtime and PLATFORM=linux-cuda; for Jetson use Dockerfile against
# nvcr.io/nvidia/l4t-jetpack with PLATFORM=jetson (see .github/workflows/build.yml).

ARG BASE=ubuntu:24.04

FROM ${BASE} AS build
ARG PLATFORM=linux
ENV DEBIAN_FRONTEND=noninteractive PROFILE=decode-all
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential clang nasm yasm cmake meson ninja-build pkg-config \
      autoconf automake libtool git curl xz-utils ca-certificates patchelf python3-pip \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY scripts/ scripts/
RUN PLATFORM=${PLATFORM} PROFILE=${PROFILE} PREFIX=/opt/ffmpeg-free BUILD_DATE=docker JOBS="$(nproc)" \
      bash scripts/build-ffmpeg.sh \
 && find /opt/ffmpeg-free/bin -type f -exec patchelf --set-rpath '$ORIGIN/../lib' {} + || true

FROM ${BASE} AS runtime
LABEL org.opencontainers.image.title="ffmpeg-free" \
      org.opencontainers.image.description="Royalty-free FFmpeg (LGPL, no GPL/nonfree, no patent-codec encoders)" \
      org.opencontainers.image.licenses="LGPL-2.1-or-later"
COPY --from=build /opt/ffmpeg-free /opt/ffmpeg-free
ENV PATH=/opt/ffmpeg-free/bin:$PATH LD_LIBRARY_PATH=/opt/ffmpeg-free/lib
RUN /opt/ffmpeg-free/bin/ffmpeg -hide_banner -version
ENTRYPOINT ["/opt/ffmpeg-free/bin/ffmpeg"]
