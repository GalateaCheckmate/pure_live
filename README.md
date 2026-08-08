<h1 align="center">
  <br>
  <img src="https://github.com/GalateaCheckmate/pure_live/blob/master/assets/icons/icon.png" width="150"/>
  <br>
  纯粹直播（Pure Live）
  <br>
</h1>

<h4 align="center">Windows 专用的第三方多平台直播聚合播放器</h4>

<p align="center">
  <img alt="License" src="https://img.shields.io/github/license/GalateaCheckmate/pure_live?color=blue">
  <img alt="Latest Release" src="https://img.shields.io/github/v/release/GalateaCheckmate/pure_live">
</p>

> 本项目仅用于个人学习与技术交流。直播内容的版权归原平台及权利人所有。

## 支持的直播平台

- 哔哩哔哩（Bilibili）
- 抖音（Douyin）
- 虎牙直播（Huya）
- 斗鱼直播（Douyu）
- 快手（Kuaishou）
- 网易 CC 直播
- 自定义 M3U/M3U8 源

## 当前功能

- Windows x64 桌面客户端
- 多平台直播间聚合与收藏
- 多播放器播放与弹幕显示
- B站扫码登录及登录态复用
- 直播源码流录制与任务恢复
- WebDAV 和本地配置备份
- 开机自启、托盘和单实例运行

## Windows 本地运行

仓库固定使用 Flutter `3.44.8`。安装 Flutter 和 Visual Studio Windows 桌面开发工具链后，可在仓库根目录双击：

```text
启动本地测试.bat
```

脚本会优先使用 FVM，否则使用系统 Flutter，并依次执行：

```powershell
flutter pub get
flutter run -d windows
```

## 验证流程

日常代码验证使用 **Windows Quick Check**：

- `flutter analyze`
- `flutter test`

完整交付验证使用手动触发的 **Windows Full Build**：

- 依赖解析
- 静态分析
- 测试
- Windows Release 构建
- 便携版构建产物
- Windows 体积基线报告

## 项目说明

- 本仓库当前只维护 Windows 版本。
- Cookie 和账号凭据仅用于对应平台的本地请求。
- 本项目不提供会员破解、付费内容绕过或直播源盗链服务。
- 问题反馈请提交到本仓库的 [Issues](https://github.com/GalateaCheckmate/pure_live/issues)。

## 上游与许可证

本仓库 Fork 自 [liuchuancong/pure_live](https://github.com/liuchuancong/pure_live)，并保留原项目贡献记录。

项目遵循 [GPL-3.0](LICENSE) 许可证。
