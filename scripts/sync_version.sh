#!/bin/bash
# sync_version.sh — 自动同步版本号：从 git tag → pubspec.yaml
#
# 用法:
#   本地:            ./scripts/sync_version.sh
#   CI/CD:           ./scripts/sync_version.sh
#   手动指定版本:     ./scripts/sync_version.sh 1.3.0
#
# 版本号规则:
#   - git tag 格式: v1.3.0  → pubspec: 1.3.0+130
#   - 手动传入格式: 1.3.0   → pubspec: 1.3.0+130
#   - build 号 = 版本号去点并去前导零（如 1.0.9 → 109）

set -euo pipefail

# 确定版本号来源
if [ $# -ge 1 ]; then
    # 手动传入版本号
    VERSION="$1"
else
    # 从最近的 git tag 获取
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [ -z "$VERSION" ]; then
        echo "ERROR: 找不到 git tag 也没有传入版本号"
        echo "用法: $0 [版本号]"
        echo "示例: $0 1.3.0"
        exit 1
    fi
fi

# 去掉前导 v（如果有）
VERSION="${VERSION#v}"

# 计算 build 号: 去掉所有点，合并为数字
BUILD_NUMBER=$(echo "$VERSION" | tr -d '.')

# 更新 pubspec.yaml
sed -i "s/^version: .*/version: ${VERSION}+${BUILD_NUMBER}/" pubspec.yaml

echo "✅ pubspec.yaml 已同步: version: ${VERSION}+${BUILD_NUMBER}"
