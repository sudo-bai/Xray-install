#!/bin/bash

# 需要 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

# 检测依赖
if ! command -v curl >/dev/null || ! command -v gpg >/dev/null; then
    apt-get update
    apt-get install -y curl gnupg
fi

# 变量配置 (用户 fork 后，这些 URL 会变，这里使用变量)
# 请替换为你的 GitHub 用户名或组织名
GITHUB_USER="sudo-bai" 
REPO_NAME="Xray-install"
CODENAME="stable"

KEY_URL="https://${GITHUB_USER}.github.io/${REPO_NAME}/public.key"
REPO_URL="https://${GITHUB_USER}.github.io/${REPO_NAME}"

echo "Adding Xray APT repository..."

# 1. 下载并转换 GPG Key
curl -fsSL "$KEY_URL" | gpg --dearmor -o /usr/share/keyrings/xray-archive-keyring.gpg

# 2. 添加 sources.list 条目
echo "deb [signed-by=/usr/share/keyrings/xray-archive-keyring.gpg] $REPO_URL $CODENAME main" > /etc/apt/sources.list.d/xray.list

# 3. 更新
echo "Updating apt cache..."
apt-get update

echo "Done! You can now install xray with: apt install xray"