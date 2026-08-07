# 发布 flv_lzc 到 pub.dev

## 准备工作

### 1. 确保所有文件已更新
- ✅ `pubspec.yaml` - 包名、版本号、描述
- ✅ `README.md` - 完整的文档和示例
- ✅ `CHANGELOG.md` - 版本更新日志
- ✅ `LICENSE` - MIT 许可证
- ✅ `example/pubspec.yaml` - 示例应用配置

### 2. 验证包结构
```bash
cd /Users/apple/Documents/Explore_Code/flv_lzc
flutter pub get
flutter analyze
```

### 3. 检查发布前的问题
```bash
flutter pub publish --dry-run
```

这个命令会检查：
- 包名是否可用
- 文件结构是否正确
- 是否有警告或错误
- 包大小是否合理

## 发布步骤

### 步骤 1: 登录 pub.dev 账号

如果还没有登录过，运行：
```bash
flutter pub login
```

这会打开浏览器，让你登录 Google 账号并授权。

### 步骤 2: 执行 dry-run 测试

```bash
cd /Users/apple/Documents/Explore_Code/flv_lzc
flutter pub publish --dry-run
```

仔细检查输出，确保没有错误或警告。

### 步骤 3: 正式发布

```bash
flutter pub publish
```

系统会提示确认，输入 `y` 确认发布。

### 步骤 4: 验证发布

发布成功后，访问：
```
https://pub.dev/packages/flv_lzc
```

确认包已经成功发布并且信息正确。

## 重要提示

### ⚠️ 发布前必须检查

1. **包名唯一性**: `flv_lzc` 在 pub.dev 上必须是唯一的
2. **版本号**: 第一次发布使用 `1.0.0`
3. **GitHub 仓库**: 更新 `pubspec.yaml` 中的 repository URL
4. **示例代码**: 确保 example 可以正常运行

### 📝 版本号规范

遵循语义化版本（Semantic Versioning）：
- **主版本号 (Major)**: 不兼容的 API 修改
- **次版本号 (Minor)**: 向下兼容的功能性新增
- **修订号 (Patch)**: 向下兼容的问题修正

示例：
- `1.0.0` - 初始发布
- `1.0.1` - Bug 修复
- `1.1.0` - 新功能
- `2.0.0` - 破坏性更改

### 🔄 更新已发布的包

1. 修改代码
2. 更新 `CHANGELOG.md`
3. 更新 `pubspec.yaml` 中的版本号
4. 运行 `flutter pub publish --dry-run`
5. 运行 `flutter pub publish`

### 📦 包内容

发布的包会包含：
- `lib/` - Dart 代码
- `android/` - Android 原生代码
- `ios/` - iOS 原生代码
- `example/` - 示例应用
- `README.md` - 文档
- `CHANGELOG.md` - 更新日志
- `LICENSE` - 许可证
- `pubspec.yaml` - 包配置

**不会包含**：
- `.git/` - Git 仓库
- `.idea/` - IDE 配置
- `build/` - 构建产物

## 发布后的维护

### 1. 监控反馈
- 查看 pub.dev 上的评分和反馈
- 关注 GitHub Issues
- 回复用户问题

### 2. 持续更新
- 修复 Bug
- 添加新功能
- 更新依赖
- 保持与最新 Flutter 版本兼容

### 3. 文档维护
- 更新 README.md
- 添加更多示例
- 完善 API 文档

## 常见问题

### Q: 包名已被占用怎么办？
A: 选择另一个唯一的包名，例如 `flv_lzc_player`

### Q: 发布失败怎么办？
A: 检查错误信息，通常是：
- 包名冲突
- 版本号问题
- 文件结构不正确
- 缺少必要文件

### Q: 如何撤回已发布的版本？
A: pub.dev 不支持删除已发布的版本，只能发布新版本覆盖

### Q: 如何设置包的可见性？
A: 默认所有包都是公开的，无法设置为私有

## 参考链接

- [pub.dev 官方文档](https://dart.dev/tools/pub/publishing)
- [Flutter 插件开发指南](https://flutter.dev/docs/development/packages-and-plugins/developing-packages)
- [语义化版本规范](https://semver.org/lang/zh-CN/)
