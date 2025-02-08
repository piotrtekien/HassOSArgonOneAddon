ARG BUILD_ARCH=amd64
ARG BUILD_FROM=ghcr.io/hassio-addons/base:${BUILD_ARCH}:9.1.7

FROM $BUILD_FROM

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV LANG=C.UTF-8
WORKDIR /data

RUN apk add i2c-tools=4.2-r0 --no-cache

COPY run.sh /
RUN chmod a+x /run.sh

CMD ["/run.sh"]
