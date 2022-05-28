rm -rf bin
podman stop ffmpeg-linux-copy-out
podman container rm ffmpeg-linux-copy-out
podman image rm ffmpeg-linux-copy-out