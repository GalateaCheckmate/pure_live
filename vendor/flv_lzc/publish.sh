#!/bin/bash

# flv_lzc 发布脚本
# 用于快速发布插件到 pub.dev

set -e  # 遇到错误立即退出

echo "🚀 flv_lzc 发布脚本"
echo "===================="
echo ""

# 检查当前目录
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ 错误: 请在 flv_lzc 根目录运行此脚本"
    exit 1
fi

# 检查包名
PACKAGE_NAME=$(grep "^name:" pubspec.yaml | awk '{print $2}')
if [ "$PACKAGE_NAME" != "flv_lzc" ]; then
    echo "❌ 错误: 包名不正确，当前为 $PACKAGE_NAME"
    exit 1
fi

echo "📦 包名: $PACKAGE_NAME"
echo ""

# 步骤 1: 清理和获取依赖
echo "1️⃣  清理并获取依赖..."
flutter clean
flutter pub get
echo "✅ 依赖获取完成"
echo ""

# 步骤 2: 代码分析
echo "2️⃣  运行代码分析..."
flutter analyze || echo "⚠️  存在分析警告，但可以继续"
echo ""

# 步骤 3: Dry-run 测试
echo "3️⃣  运行 dry-run 测试..."
flutter pub publish --dry-run
echo ""

# 询问是否继续
echo "📋 Dry-run 测试完成！"
echo ""
read -p "是否继续正式发布到 pub.dev? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ 取消发布"
    exit 0
fi

# 步骤 4: 正式发布
echo ""
echo "4️⃣  正式发布到 pub.dev..."
flutter pub publish

echo ""
echo "🎉 发布完成！"
echo ""
echo "📝 后续步骤:"
echo "1. 访问 https://pub.dev/packages/flv_lzc 验证发布"
echo "2. 检查包信息是否正确"
echo "3. 测试安装: flutter pub add flv_lzc"
echo ""
