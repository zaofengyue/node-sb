FROM node:20-alpine
WORKDIR /app
COPY package.json index.js index.html ./

RUN apk add --no-cache curl tar openssl

RUN mkdir -p /root/sing-box && \
    curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v1.13.13/sing-box-1.13.13-linux-amd64.tar.gz" \
    | tar -xz --strip-components=1 -C /root/sing-box && \
    chmod +x /root/sing-box/sing-box && \
    /root/sing-box/sing-box version

CMD ["node", "index.js"]
