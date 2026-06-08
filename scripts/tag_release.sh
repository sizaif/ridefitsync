#!/bin/bash
# tag_release.sh — 打版本标签 → 同步 pubspec → 提交 → 推送
#
# 用法:
#   ./scripts/tag_release.sh 1.3.0
#
# 实际执行:
#   1. 同步 pubspec.yaml 版本号
#   2. 提交版本号变更
#   3. 创建 git tag v1.3.0
#   4. 推送到远程（可选）

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "用法: $0 <版本号>"
    echo "示例: $0 1.3.0"
    exit 1
fi

VERSION="$1"
TAG="v${VERSION}"

# 确保在仓库根目录
cd "$(git rev-parse --show-toplevel)"

# 1. 同步版本号到 pubspec.yaml
bash scripts/sync_version.sh "$VERSION"

# 2. 提交版本号变更
git add pubspec.yaml
git commit -m "chore(release): 同步版本号 ${VERSION} 到 pubspec.yaml" || echo "pubspec.yaml 无变更，跳过提交"

# 3. 打 tag
git tag -a "$TAG" -m "Release ${TAG}"

echo ""
echo "✅ 完成！本地操作:"
echo "   pubspec.yaml  → version: ${VERSION}"
echo "   git tag       → ${TAG}"
echo ""
echo "接下来手动推送:"
echo "   git push origin main"
echo "   git push origin ${TAG}"
echo ""
echo "推送 tag 后 GitHub Actions 将自动构建并发布 APK"
