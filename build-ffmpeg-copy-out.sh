mkdir -p bin/
podman build -t ffmpeg-linux-copy-out -f cuda-ubuntu-free.dockerfile
podman run -itd --name ffmpeg-linux-copy-out ffmpeg-linux-copy-out
podman cp ffmpeg-linux-copy-out:/app/workspace/bin/ffmpeg bin/ffmpeg
podman cp ffmpeg-linux-copy-out:/app/workspace/bin/ffprobe bin/ffprobe
podman stop ffmpeg-linux-copy-out
podman container rm ffmpeg-linux-copy-out