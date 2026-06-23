#!/bin/sh
# ============================================================================
# Radiance OCI Bot 客户端容器入口脚本
#
# 路径设计：
#   /opt/rbot  —— 镜像内置只读区：r_client(二进制) + client_config.template
#   /app       —— 用户数据区（挂载卷）：client_config、*.pem、data/、.task/
#
# 职责：
#   1. 首次启动时从模板生成 client_config（仅当挂载卷里不存在时）
#   2. 创建数据目录 data/（SSL 证书）、.task/（任务）
#   3. 通过环境变量 MODEL / PORT 覆盖配置
#   4. exec 启动 r_client，让二进制成为 PID 1 接收 SIGTERM 优雅退出
#
# 兼容 Alpine busybox 的 /bin/sh（不使用 bash 特有语法）。
# ============================================================================

set -eu

# 镜像内置只读区（绝不挂载覆盖）
BIN_DIR="/opt/rbot"
TEMPLATE="${BIN_DIR}/client_config.template"
BINARY="${BIN_DIR}/r_client"

# 用户数据区（挂载卷）
APP_DIR="/app"
CONFIG="${APP_DIR}/client_config"

cd "${APP_DIR}"

# ----------------------------------------------------------------------------
# 0. 健全性检查：二进制必须在（若被挂载盖掉会立刻暴露）
# ----------------------------------------------------------------------------
if [ ! -x "${BINARY}" ]; then
    echo "[entrypoint] 致命错误: 找不到可执行二进制 ${BINARY}" >&2
    echo "[entrypoint] 请确认你没有把宿主目录挂载到 ${BIN_DIR}，只应挂载到 ${APP_DIR}(/app)" >&2
    exit 1
fi

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
#    注意：必须用"读全部 → shell 替换 → 回写"，不能用 sed -i。
#    sed -i 会新建临时文件再 rename 覆盖，但当 client_config 作为
#    【单文件 bind mount】时目标 inode 被 docker 绑定，rename 会报
#    "Resource busy"（群晖/容器里尤其明显）。下面用 sed 生成新内容到
#    临时文件、再 cat 回写原 inode（truncate+write，bind mount 允许），
#    避免任何 rename。
# ----------------------------------------------------------------------------
if [ -n "${MODEL:-}" ]; then
    if grep -q '^model=' "${CONFIG}" 2>/dev/null; then
        tmpfile="${APP_DIR}/.client_config.tmp.$$"
        if sed "s|^model=.*|model=${MODEL}|" "${CONFIG}" > "${tmpfile}" 2>/dev/null; then
            # cat 回写：truncate + write 到同一 inode，对 bind mount 安全
            cat "${tmpfile}" > "${CONFIG}"
            rm -f "${tmpfile}"
        else
            rm -f "${tmpfile}"
            echo "[entrypoint] 注意: MODEL 覆盖失败，沿用 client_config 内现有 model 值" >&2
        fi
    else
        printf '\nmodel=%s\n' "${MODEL}" >> "${CONFIG}"
    fi
fi

PORT="${PORT:-9527}"

echo "[entrypoint] 启动 r_client (model=$(grep '^model=' "${CONFIG}" 2>/dev/null | head -1 | cut -d= -f2- || echo unset), port=${PORT})"

# ----------------------------------------------------------------------------
# 4. 启动
#    exec 使 r_client 取代 shell 成为 PID 1，正确接收 docker stop 的 SIGTERM。
# ----------------------------------------------------------------------------
exec "${BINARY}" \
    --server.port="${PORT}" \
    --configPath="${CONFIG}"
