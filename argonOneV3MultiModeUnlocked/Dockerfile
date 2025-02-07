# Dockerfile for Argon One V3 Advanced Fan Control Add-on (ARM only)
ARG BUILD_FROM=ghcr.io/hassio-addons/base/armv7:9.1.7
# hadolint ignore=DL3006
FROM ${BUILD_FROM}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV LANG C.UTF-8

WORKDIR /data

# Install required tools
RUN apk add --no-cache i2c-tools=4.2-r0

# Copy the runtime script
COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
