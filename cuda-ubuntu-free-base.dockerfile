ARG VER=20.04

FROM nvidia/cuda:11.4.2-devel-ubuntu${VER}

ENV DEBIAN_FRONTEND noninteractive
ENV NVIDIA_VISIBLE_DEVICES all
ENV NVIDIA_DRIVER_CAPABILITIES compute,utility,video

RUN apt-get update \
    && apt-get -y --no-install-recommends install build-essential curl ca-certificates libva-dev python3 python-is-python3 ninja-build meson \
    && apt-get clean; rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/* \
    && update-ca-certificates && \
    && apt-get install -y vdpau-driver-all mesa-vdpau-drivers mesa-va-drivers libvdpau-dev vdpauinfo

WORKDIR /app
COPY ./build-ffmpeg /app/build-ffmpeg