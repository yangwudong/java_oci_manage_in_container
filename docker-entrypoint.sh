#!/bin/sh
# ============================================================================
# Radiance OCI Bot 客户端容器入口脚本
#
# 职责：
#   1. 首次启动时从模板生成 client_config（仅当挂载卷里不存在时）
#   2. 创建数据目录 data/（SSL 证书）、.task/（任务）
#   3. 通过环境变量 MODEL / PORT 覆盖配置（便于 docker run / 群晖 UI 修改）
#   4. exec 启动 r_client，让二进制成为 PID 1 接收 SIGTERM 优雅退出
#
# 兼容 Alpine busybox 的 /bin/sh（不使用 bash 特有语法）。
# ============================================================================

set -eu

APP_DIR="/app"
CONFIG="${APP_DIR}/client_config"
TEMPLATE="${APP_DIR}/client_config.template"
BINARY="${APP_DIR}/r_client"

cd "${APP_DIR}"

# ----------------------------------------------------------------------------
# 1. 首次初始化配置文件
#    若挂载目录里没有 client_config，则用镜像内置模板生成一份。
#    已存在的配置绝不覆盖（保护用户的 API 凭据）。
# ----------------------------------------------------------------------------
if [ ! -f "${CONFIG}" ]; then
    if [ -f "${TEMPLATE}" ]; then
        cp -f "${TEMPLATE}" "${CONFIG}"
        echo "[entrypoint] 已从模板生成 ${CONFIG}，请编辑后重启容器填入你的配置。"
    else
        echo "[entrypoint] 警告: 未找到配置模板 ${TEMPLATE}，将创建空配置。" >&2
        : > "${CONFIG}"
    fi
fi

# ----------------------------------------------------------------------------
# 2. 建立运行时目录
#    data/  存放程序生成的自签 SSL 证书
#    .task/ 存放任务数据
# ----------------------------------------------------------------------------
mkdir -p "${APP_DIR}/data" "${APP_DIR}/.task"

# ----------------------------------------------------------------------------
# 3. 环境变量覆盖
#    MODEL:  local=本地无公网IP模式（容器推荐，只要能出站即可）
#            其它/空=端口模式（需端口能被 bot 访问，适合公网/反代）
#    PORT:   监听端口（默认 9527）
#
#    用 sed 原地修改 client_config 中以 model= 开头的行；
#    若文件中没有该行（用户删过），则追加。
# ----------------------------------------------------------------------------
if [ -n "${MODEL:-}" ]; then
    if grep -q '^model=' "${CONFIG}"; then
        # busybox sed -i 需要后跟空字符串
        sed -i "s|^model=.*|model=${MODEL}|" "${CONFIG}"
    else
        printf '\nmodel=%s\n' "${MODEL}" >> "${CONFIG}"
    fi
fi

PORT="${PORT:-9527}"

echo "[entrypoint] 启动 r_client (model=$(grep '^model=' "${CONFIG}" 2>/dev/null || echo unset), port=${PORT})"

# ----------------------------------------------------------------------------
# 4. 启动
#    exec 使 r_client 取代 shell 成为 PID 1，正确接收 docker stop 的 SIGTERM。
# ----------------------------------------------------------------------------
exec "${BINARY}" \
    --server.port="${PORT}" \
    --configPath="${CONFIG}"
