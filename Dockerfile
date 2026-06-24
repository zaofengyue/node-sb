FROM node:20-alpine
WORKDIR /app
COPY package.json index.js index.html ./
RUN apk add --no-cache curl unzip tar openssl

RUN set -e && \
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/;s/armv7l/armv7/') && \
    mkdir -p /root/sing-box && \
    curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v1.13.13/sing-box-1.13.13-linux-${ARCH}.tar.gz" \
    | tar -xz --strip-components=1 -C /root/sing-box && \
    chmod +x /root/sing-box/sing-box && \
    /root/sing-box/sing-box version

CMD ["node", "index.js"]
