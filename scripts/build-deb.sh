#!/bin/bash

# 错误中断
set -e

VERSION=$1
ARCH=$2
OUTPUT_DIR=$3

if [[ -z "$VERSION" || -z "$ARCH" || -z "$OUTPUT_DIR" ]]; then
    echo "Usage: $0 <version> <arch> <output_dir>"
    echo "Example: $0 1.8.4 amd64 ./dist"
    exit 1
fi

# 映射 Xray 的架构名称到 Debian 架构名称
case "$ARCH" in
    amd64)
        XRAY_ARCH="64"
        DEB_ARCH="amd64"
        ;;
    arm64)
        XRAY_ARCH="arm64-v8a"
        DEB_ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

WORK_DIR=$(mktemp -d)
PKG_ROOT="$WORK_DIR/pkg"
mkdir -p "$PKG_ROOT/usr/local/bin"
mkdir -p "$PKG_ROOT/usr/local/share/xray"
mkdir -p "$PKG_ROOT/usr/local/etc/xray"
mkdir -p "$PKG_ROOT/etc/systemd/system"
mkdir -p "$PKG_ROOT/var/log/xray"
mkdir -p "$PKG_ROOT/DEBIAN"

echo "Downloading Xray-core v$VERSION for $ARCH..."
DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/v${VERSION}/Xray-linux-${XRAY_ARCH}.zip"
curl -L -o "$WORK_DIR/xray.zip" "$DOWNLOAD_URL"
unzip -q "$WORK_DIR/xray.zip" -d "$WORK_DIR/extract"

# 安装二进制文件
install -m 755 "$WORK_DIR/extract/xray" "$PKG_ROOT/usr/local/bin/xray"
install -m 644 "$WORK_DIR/extract/geoip.dat" "$PKG_ROOT/usr/local/share/xray/geoip.dat"
install -m 644 "$WORK_DIR/extract/geosite.dat" "$PKG_ROOT/usr/local/share/xray/geosite.dat"

# 生成 systemd 服务文件 (直接写入，保持与 install-release.sh 一致)
cat > "$PKG_ROOT/etc/systemd/system/xray.service" <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=nobody
# 在 Debian/Ubuntu 上，nobody 的默认组通常是 nogroup
# 如果不指定 Group，systemd 会使用用户的默认组
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000
RuntimeDirectory=xray
RuntimeDirectoryMode=0755

[Install]
WantedBy=multi-user.target
EOF

# 生成 control 文件
# Version 去掉 v 前缀
CLEAN_VERSION="${VERSION#v}"

cat > "$PKG_ROOT/DEBIAN/control" <<EOF
Package: xray
Version: $CLEAN_VERSION
Section: net
Priority: optional
Architecture: $DEB_ARCH
Maintainer: Xray-install <https://github.com/XTLS/Xray-install>
Description: A unified platform for anti-censorship.
 Xray-core packaged for Debian/Ubuntu.
EOF

# 生成 postinst 脚本 (用于设置权限和创建初始配置)
cat > "$PKG_ROOT/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e

if [ "\$1" = "configure" ]; then
    # 确保存放配置文件的目录存在
    if [ ! -f /usr/local/etc/xray/config.json ]; then
        echo "{}" > /usr/local/etc/xray/config.json
    fi
    
    # 设置日志目录权限
    # 修复：Debian/Ubuntu 上 nobody 用户的组名通常是 nogroup，而不是 nobody
    # 使用 getent 检查 nogroup 组是否存在
    if getent group nogroup >/dev/null 2>&1; then
        chown nobody:nogroup /var/log/xray
    else
        # 备用方案：如果 nogroup 不存在，尝试使用 nobody 组 (兼容非 Debian 系统)
        chown nobody:nobody /var/log/xray
    fi
    
    # 重载 systemd
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload
        # 如果是首次安装，不自动启动，遵循 Debian 策略，或者根据需求开启
        # systemctl enable xray
    fi
fi
EOF
chmod 755 "$PKG_ROOT/DEBIAN/postinst"

# 生成 prerm 脚本
cat > "$PKG_ROOT/DEBIAN/prerm" <<EOF
#!/bin/sh
set -e

if [ "\$1" = "remove" ]; then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop xray || true
        systemctl disable xray || true
    fi
fi
EOF
chmod 755 "$PKG_ROOT/DEBIAN/prerm"

# 构建 .deb
mkdir -p "$OUTPUT_DIR"
dpkg-deb --build "$PKG_ROOT" "$OUTPUT_DIR/xray_${CLEAN_VERSION}_${DEB_ARCH}.deb"

echo "Build complete: $OUTPUT_DIR/xray_${CLEAN_VERSION}_${DEB_ARCH}.deb"
rm -rf "$WORK_DIR"