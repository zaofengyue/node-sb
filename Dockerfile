FROM node:20-alpine
WORKDIR /app
COPY package.json index.js index.html ./
RUN apk add --no-cache curl unzip tar openssl

# 构建时预下载 sing-box，避免运行时依赖 GitHub
RUN set -e && \
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/;s/armv7l/armv7/') && \
    VER=$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest \
          | grep '"tag_name"' | cut -d'"' -f4) && \
    mkdir -p /root/sing-box && \
    curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/${VER}/sing-box-${VER#v}-linux-${ARCH}.tar.gz" \
    | tar -xz --strip-components=1 -C /root/sing-box && \
    chmod +x /root/sing-box/sing-box

CMD ["node", "index.js"]
