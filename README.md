# 时说（daily_planner）

> 用说的就能规划日程的语音规划 App。核心价值：**你的时间，不该撞车。**

一款**纯前端** Flutter 应用，所有数据本地存储（SQLite），云端大模型（阿里云百炼 / DashScope）为**可选增强**——不配置也能完整使用（自动退回本地 NLP 解析）。

## 功能特性

### 任务模块
- **定时提醒**：指定时间 / 倒计时（一次性或按间隔重复）录入；重复支持每天 / 每周 / 工作日 / 自定义星期。系统级精确调度（`flutter_local_notifications` + `timezone`），应用被杀仍弹通知；应用存活时到点响铃 + 中文语音播报 + 震动（震动可叠加静音，持续整个响铃时长）
- **语音规划**：说一句口语 → 云端大模型排期（`qwen3.7-max`）解析为结构化任务；录音转写实时插入光标处；云端不可用自动退回本地 NLP
- **冲突检测**：时间重叠 = 时段相交；资源占用冲突 = 时间重叠且同资源重复占用，标红拦截；支持改时间 / 换资源 / 确认覆盖
- **任务管理**：全部 / 进行中 / 冲突 / 已完成四态筛选，详情抽屉编辑，滑动删除 / 长按批量删除

### 记事本模块
- **六大类记录**：旅游计划、账本、购物清单、阅读、菜谱、学习记录，语音速记 + 结构化存储
- **购物模块**：购物车列表 + 单行记录，分类/金额校验，消费趋势报表（分类占比、天/月/年维度）

### 我的（个人中心）
- 资料编辑（昵称/头像）、JSON 备份导入导出（确认弹窗 + 格式校验）、通知权限引导（实时回显）、播报音色切换（系统 TTS 语音）、**深色模式三档**（跟随系统/浅色/深色，全局生效并持久化）

### 提醒与响铃
- 铃铛设置：静音 / 语音播报互斥、震动独立叠加、音量滑杆
- 到点：系统通知 + 语音播报 + 持续震动；静音模式仅通知 + 震动

## 技术栈

| 能力 | 方案 |
|------|------|
| 开发框架 | Flutter 3.44 + Dart 3.12 |
| 本地存储 | SQLite（sqflite），含版本化迁移与旧版 Hive 数据迁移 |
| 状态管理 | Provider |
| 通知 / 精确调度 | `flutter_local_notifications` + `timezone` |
| 响铃 / 播报 | `just_audio` + `audio_session`（alarm 会话）、`flutter_tts` 中文播报 |
| 震动 | 原生 Vibrator（循环波形持续震动，静音可叠加） |
| 录音采集 | `record`（PCM16 采集 + 重采样） |
| 云端接入 | `http`（DashScope OpenAI 兼容 `/chat/completions`），排期与 ASR 共用 `DASHSCOPE_API_KEY` |
| 权限 | `permission_handler` |
| 工具 | `intl` / `uuid` / `yaml` / `path_provider` / `share_plus` / `file_selector` |

## 快速开始

```bash
# 前置：Flutter 3.44.x stable
flutter pub get

# 本地运行（连接 Android/iOS 设备或模拟器）
flutter run

# 构建 Android 安装包（输出 build/app/outputs/flutter-apk/）
flutter build apk --release
```

首次运行会请求**麦克风 / 通知 / 精确闹钟**权限；未配置云端密钥时自动走「本地 NLP + 设备端识别」，开箱即用。

## 接入阿里云（可选）

```bash
export DASHSCOPE_API_KEY=sk-xxxx
export DASHSCOPE_BASE_URL=https://llm-xxxx.maas.aliyuncs.com/api/v1   # 可覆盖默认端点
```

真实 Key 写入 `lib/config/secrets.dart`（**已被 .gitignore 忽略**，首次克隆后从 `secrets.dart.example` 复制填值）。

> ⚠️ 把 API Key 打包进前端仅适合 Demo / 内测；生产环境应由后端代理持有密钥。

## 测试与质量

```bash
flutter test        # 全量单元测试（当前 395 项全绿）
flutter analyze     # 静态分析（0 error 通过）
```

## CI/CD 与 APK 下载

仓库配置了 GitHub Actions 自动化（详见 [OPERATION.md](OPERATION.md)）：

- **CI**：push/PR 到 main 自动执行分析 + 全量测试 + 构建 Android APK（产物在 Actions 页保留 14 天）
- **Release**：推送 `v*` tag 自动构建并发布 **GitHub Release**，APK 可直接下载安装

```bash
git tag v1.0.0 && git push origin v1.0.0
# 等待 Release 工作流完成 → 仓库 Releases 页下载 app-release.apk 直接安装
```

### iOS 打包

可以打包，但**真机安装/上架需 Apple Developer 账号（99 美元/年）+ 证书签名**；
免费账号仅能产出模拟器 / 无签名构建。CI 已内置可选 iOS 任务（默认关闭），
启用与所需环境变量见 [OPERATION.md](OPERATION.md) 第五节。

## 已知限制

1. 密钥前端直连仅限 Demo：生产需走后端代理。
2. 应用被杀后仅系统通知（响铃/播报在应用存活时最佳）。
3. 重复任务冲突判定为未来 30 天窗口近似展开。
4. 本地 NLP 为启发式解析，极口语化表述可能需手动校正。

## 许可与约定

- 仓库只包含源代码：工作文档（docs/、design/ 等）与私密文件（secrets.dart、签名文件）不入库。
- 详细操作指引见 [OPERATION.md](OPERATION.md)。
