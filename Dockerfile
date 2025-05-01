# Use the official n8n image as the base
FROM docker.n8n.io/n8nio/n8n

# Switch to root user to install packages
USER root

# Update package lists and install FFmpeg
# Clean up apt cache afterwards to keep image size down
# Update apk cache and install ffmpeg
# --no-cache cleans up the cache automatically afterwards
RUN apk update && \
    apk add --no-cache ffmpeg

# Switch back to the default node user
USER node