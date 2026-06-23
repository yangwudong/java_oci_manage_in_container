# java_oci_manage 容器化封装

> [Radiance OCI Bot (R-Bot)](https://github.com/semicons/java_oci_manage) 客户端的**非官方** Docker 多架构镜像。
> 把上游发布的静态二进制 `r_client` 封装进极小的 Alpine 镜像，开箱即用，一份镜像覆盖群晖 NAS / Windows / macOS。

---

## 📦 镜像信息

| 项 | 值 |
|---|---|
| Docker Hub | `yangwudong/java_oci_manage` |
| 架构 | `linux/amd64`、`linux/arm64`（多架构 manifest，自动按主机选择） |
| 基础镜像 | `alpine:3.20` |
| 端口 | `9527`（HTTPS） |
| 上游项目 | https://github.com/semicons/java_oci_manage |
| 当前封装版本 | `v10.1.3` |

**amd64 用的是上游的 `_compatible` 包**（不依赖 AVX/AVX2/SSE4.2），兼容群晖常见的 Intel Celeron/Atom 机型（J3455 / J4125 / N5095 等）。这与上游官方安装脚本的兼容性检测逻辑一致。

---

## 🚀 快速开始

```bash
docker run -d \
  --name rbot \
  --restart unless-stopped \
  -p 9527:9527 \
  -v /your/host/path/rbot:/app \
  -e TZ=Asia/Shanghai \
  yangwudong/java_oci_manage:latest
```

首次启动后，容器会在挂载目录生成默认配置 `client_config`（`model=local` 本地模式）。编辑它填入你的 bot 用户名/密码和甲骨文 API 信息，然后重启容器：

```bash
docker restart rbot
```

---

## 🖥️ 各平台部署

### 群晖 NAS（Container Manager）

1. **建目录**：File Station 在 `/volume1/docker/` 下新建文件夹 `rbot`。
2. **拉镜像**：Container Manager → 注册表 → 搜索 `yangwudong/java_oci_manage` → 下载 `latest`（DSM 会自动按你的 CPU 架构选 amd64 或 arm64）。
3. **建容器**：映像 → 选中 → 启动，做如下设置：
   - **存储空间**：添加文件夹映射 `/volume1/docker/rbot` → 装载路径 `/app`
   - **端口**：本地端口自选 → 容器端口 `9527`
   - **环境变量**：`TZ=Asia/Shanghai`
   - **重启策略**：除非停止
4. **配置**：容器启动一次后会在 `/volume1/docker/rbot/` 生成 `client_config`，编辑它（File Station 右键编辑或用文本编辑器套件），填好配置后重启容器。

### Windows / macOS

安装 [Docker Desktop](https://www.docker.com/products/docker-desktop/)，然后执行上面的「快速开始」命令即可。Docker Desktop 会自动拉取与本机架构匹配的镜像（Apple Silicon 拉 arm64，Intel Mac / Windows 拉 amd64）。

> 注：Docker 只运行 Linux 容器，因此 macOS 上跑的也是 `linux/arm64` 镜像，完全正常。

---

## ⚙️ 配置说明

所有配置集中在挂载目录的 **`client_config`** 文件里。首次启动自动生成模板，关键字段：

```ini
# 必填：从 bot 处获取（@radiance_helper_bot 用 /raninfo 命令生成）
username=
password=

# 启动模式：local=本地无公网IP模式（容器推荐，仅需出站联网）
# 留空或改其它值=端口模式（需 bot 能访问到你的 9527 端口，适合公网/反代）
model=local

# 甲骨文 API（oci=begin / oci=end 之间，可放多个 profile）
oci=begin
[DEFAULT]
user=ocid1.user...
fingerprint=xx:xx...
tenancy=ocid1.tenancy...
region=ap-singapore-1
key_file=/app/your-key.pem      # 私钥文件放到挂载目录，路径写 /app/xxx.pem
oci=end
```

### API 私钥文件

甲骨文 API 私钥 `.pem` 文件放在**挂载目录**（即容器内 `/app/`），配置里 `key_file` 写 `/app/你的文件名.pem`。

### 持久化数据

挂载目录 `/app` 内会保存：

| 文件/目录 | 作用 |
|---|---|
| `client_config` | 主配置（含 API 凭据，最重要） |
| `*.pem` | 甲骨文 API 私钥 |
| `data/` | 运行时数据目录 |
| `.task/` | 任务数据 |
| `log_r_client.log` | 运行日志 |

升级镜像时这些文件随挂载目录保留，**不会丢失**。

### 路径架构（重要）

为避免挂载卷覆盖镜像内的二进制，容器内分两个目录：

| 路径 | 说明 | 是否挂载 |
|---|---|---|
| `/opt/rbot` | 镜像内置只读区：二进制 `r_client` + 配置模板 | ❌ 永不挂载 |
| `/app` | 用户数据区：配置/私钥/任务/日志 | ✅ 挂载到这里 |

> **只需挂载 `/app`**。二进制随镜像升级，不会也不应被宿主目录覆盖。

---

## 🌍 环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `PORT` | `9527` | 监听端口。改了之后**主机端口映射**也要同步改 |
| `MODEL` | `local` | 启动模式，每次容器启动时覆盖 `client_config` 里的 `model=`。设为空串 `MODEL=` 切回端口模式 |
| `TZ` | `Asia/Shanghai` | 时区，影响日志和定时任务 |

例如想用 8888 端口 + 端口模式：

```bash
docker run -d --name rbot -p 8888:8888 -v /your/path:/app \
  -e PORT=8888 -e MODEL= -e TZ=Asia/Shanghai \
  yangwudong/java_oci_manage:latest
```

---

## 🔒 HTTPS / SSL 证书

**r_client 内置完整的 ACME 自动证书功能，无需手动挂载证书文件。**

通过 Web 面板 `设置 → SSL Certificate (ACME)` 配置，支持两种签发方式：

| 方式 | 验证 | 前置条件 | 适合场景 |
|---|---|---|---|
| **域名模式 (DNS-01)** | Cloudflare DNS | `client_config` 填 `cf_email` + `cf_account_key`，**无需开 80 端口** | ✅ NAS / 内网（推荐） |
| **IP 模式 (HTTP-01)** | HTTP | 签发时临时开 80 端口 | 公网 IP 服务器 |

### NAS 上用 acme 证书的正确做法

1. 先在 `client_config` 填 Cloudflare 凭据（域名要托管在 Cloudflare）：
   ```ini
   cf_email=你的cloudflare登录邮箱
   cf_account_key=你的Global API Key
   ```
2. 重启容器：`docker restart rbot`
3. 浏览器访问 `https://<NAS的IP>:9527/radiance-bot-client` 登录 Web 面板（首次有自签证书警告，点继续）
4. 进 `设置 → SSL Certificate (ACME)`，勾选 Enable，填域名 + 通知邮箱
5. r_client 自动通过 DNS-01 向 Let's Encrypt 申请并续期证书

> 这样 r_client 直接对外提供受信任的 HTTPS，浏览器显示绿锁，**不需要反向代理，也不用挂载任何证书文件**。
>
> 如果你更倾向用群晖自带反向代理 / Nginx Proxy Manager 统一管理证书，那让 r_client 走 HTTP、由反代终结 SSL 即可——两种方式二选一。

---

## 🔄 版本与升级

镜像跟随上游 `semicons/java_oci_manage` 的 release。

- **自动**：本仓库每周一自动检查上游是否有新版本，有则自动构建并推送新 tag（如 `v10.1.4`）+ 更新 `latest`。
- **手动**：仓库 → Actions → `Build & Publish Docker Image` → Run workflow，可指定版本号。

升级你本地的容器：

```bash
docker pull yangwudong/java_oci_manage:latest
docker rm -f rbot
# 再用原来的 docker run 命令启动（配置已持久化，不会丢）
```

镜像 tag 规则：

- `yangwudong/java_oci_manage:latest` —— 永远指向最新构建
- `yangwudong/java_oci_manage:v10.1.3` —— 版本锁定，适合生产固定版本

---

## 🔧 维护者：Secret 与首次构建设置

本仓库用 GitHub Actions 自动构建推送到 Docker Hub。Fork/使用前需配置：

1. **Docker Hub 建 Access Token**：登录 Docker Hub → Account Settings → Security → New Access Token（权限选 Read & Write）。
2. **GitHub 加 Secret**：本仓库 → Settings → Secrets and variables → Actions → New repository secret，添加：
   - `DOCKERHUB_USERNAME` = 你的 Docker Hub 用户名（如 `yangwudong`）
   - `DOCKERHUB_TOKEN` = 上一步生成的 token
3. **首次构建**：Actions → `Build & Publish Docker Image` → Run workflow。

> 镜像名 `yangwudong/java_oci_manage` 以明文写在 `.github/workflows/docker-publish.yml` 的 `env.IMAGE` 里；如需改成你自己的仓库，直接改这一行即可，token 仍走 secret，不会硬编码。

---

## 🏗️ 本地构建（可选）

```bash
# 构建 amd64（默认本机架构）
docker build -t rbot-local --build-arg UPSTREAM_VERSION=v10.1.3 .

# 构建 arm64（需先开 binfmt / QEMU 支持）
docker buildx build --platform linux/arm64 -t rbot-local:arm64 .
```

---

## ⚠️ 免责声明

本项目仅为上游 [java_oci_manage](https://github.com/semicons/java_oci_manage) 二进制文件的容器化封装，不含任何源码，版权归原作者所有。

引用上游声明：本仓库发布的项目中涉及的任何脚本，仅用于测试和学习研究，禁止用于商业用途。所有使用者在使用项目的任何部分时，需先遵守法律法规。对于一切使用不当所造成的后果，需自行承担。

使用本项目即视为你已阅读并接受上游的[完整免责声明](https://github.com/semicons/java_oci_manage#前言)。
