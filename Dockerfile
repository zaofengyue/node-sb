FROM node:20-alpine
WORKDIR /app
COPY package.json index.js index.html ./
RUN apk add --no-cache curl unzip tar openssl

RUN mkdir -p /root/sing-box && \
    curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v1.13.13/sing-box-1.13.13-linux-amd64.tar.gz" \
    -o /tmp/sb.tar.gz && \
    ls -lh /tmp/sb.tar.gz && \
    tar -tzf /tmp/sb.tar.gz && \
    tar -xzf /tmp/sb.tar.gz -C /root/sing-box --strip-components=1 && \
    ls -la /root/sing-box/ && \
    chmod +x /root/sing-box/sing-box && \
    /root/sing-box/sing-box version

CMD ["node", "index.js"]
