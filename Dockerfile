#
# java_oci_manage (Radiance OCI Bot / R-Bot 客户端) 非官方容器化封装
# 上游项目：https://github.com/semicons/java_oci_manage
#
# 上游通过 GitHub Releases 分发静态链接的原生二进制 r_client，因此镜像可极小、
# 无任何动态库依赖。本 Dockerfile 用 alpine 作为基础，仅提供运行时所需的
# ca-certificates / wget / tzdata。
#
# 多架构说明（与上游安装脚本的兼容性检测逻辑一致）：
#   - linux/amd64 -> gz_client_bot_x86_compatible.tar.gz
#       （不用 gz_client_bot_x86.tar.gz，后者需 AVX/AVX2/SSE4.2，
#        群晖 Intel 机型如 J3455/J4125/N5095 多不支持）
#   - linux/arm64 -> gz_client_bot_aarch.tar.gz

FROM alpine:3.20

# 上游版本（带 v 前缀）。构建时通过 --build-arg 覆盖。
ARG UPSTREAM_VERSION=v10.1.3
# 自动注入的目标架构（amd64 / arm64）
ARG TARGETARCH

# 静态二进制无需 glibc，但需要 SSL 根证书（与 Telegram/Oracle API 做 HTTPS）、
# wget（HEALTHCHECK 与排障）、tzdata（时区）。
RUN apk add --no-cache ca-certificates wget tzdata \
    && update-ca-certificates

WORKDIR /app

# 下载并解压上游二进制。
# 注意：上游每个 release 都保留历史包，因此版本化的 URL 可长期稳定访问。
RUN case "$TARGETARCH" in \
        amd64) PKK="gz_client_bot_x86_compatible.tar.gz" ;; \
        arm64) PKK="gz_client_bot_aarch.tar.gz" ;; \
        *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
    esac \
    && URL="https://github.com/semicons/java_oci_manage/releases/download/${UPSTREAM_VERSION}/${PKK}" \
    && echo "Downloading $URL" \
    && wget -q -O /tmp/pkg.tar.gz "$URL" \
    && mkdir -p /tmp/pkg \
    && tar -xzf /tmp/pkg.tar.gz -C /tmp/pkg \
    && if [ ! -f /tmp/pkg/r_client ]; then \
           echo "package missing r_client" >&2; exit 1; \
       fi \
    && mv /tmp/pkg/r_client /app/r_client \
    && chmod +x /app/r_client \
    # 上游模板仅作首次初始化用，真正生效的是 entrypoint 复制的那份
    # 优先用包内 client_config，缺失则用仓库内的模板兜底
    && if [ -f /tmp/pkg/client_config ]; then \
           cp -f /tmp/pkg/client_config /app/client_config.template; \
       fi \
    && rm -rf /tmp/pkg /tmp/pkg.tar.gz

# 仓库内模板作为 fallback：若上游包未携带 client_config，则用它。
COPY client_config.template /app/client_config.repo.template
RUN if [ ! -f /app/client_config.template ]; then \
        cp -f /app/client_config.repo.template /app/client_config.template; \
    fi \
    && rm -f /app/client_config.repo.template

# 复制入口脚本
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# 运行时数据目录（挂载卷会覆盖，这里只建空目录避免首次启动报错）
RUN mkdir -p /app/data /app/.task

# 默认 HTTPS 端口（上游固定）
EXPOSE 9527

# 健康检查：上游自签 HTTPS，必须忽略证书校验。
# --spider 仅探测可达性，不下载 body。
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD wget --no-check-certificate -q --spider --timeout=5 \
        "https://127.0.0.1:${PORT:-9527}/radiance-bot-client/roc/api/client/health" \
        || exit 1

# 容器内默认以非 root 运行更安全，但上游二进制在端口模式下需要绑定 9527（>1024 无需特权），
# local 模式仅出站连接，因此非 root 完全够用。
RUN addgroup -S rbot && adduser -S -G rbot -h /app rbot \
    && chown -R rbot:rbot /app
USER rbot

# 保留可覆盖端口与启动模式的环境变量入口
ENV PORT=9527 \
    MODEL=local \
    TZ=Asia/Shanghai

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
