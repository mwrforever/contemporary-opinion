# 时说 · 打包与发布操作手册（OPERATION）

> 适用对象：项目维护者。本文档覆盖本地打包、GitHub Actions 自动化构建、
> APK 发布下载、iOS 打包条件与所需环境变量配置，以及私密信息管理规范。

---

## 一、仓库内容约定

本仓库**只包含源代码**，以下内容一律不入库（.gitignore 已强制排除，且已从
历史跟踪中移除，仅保留在你本地）：

| 类别 | 目录/文件 | 说明 |
|------|-----------|------|
| 工作文档 | `docs/`、`design/`、`design-system/`、`FEATURES.md`、`PROGRESS.md`、`PROJECT_INTRO.md` | 设计稿、计划、冒烟清单等 |
| 私密配置 | `lib/config/secrets.dart` | 真实 API Key（见第三节） |
| 签名文件 | `android/key.properties`、`android/*.jks`、`*.keystore` | Android 签名 |
| 本地工具 | `.agents/`、`.claude/`、`.superpowers/`、`.playwright/`、`.workbuddy/`、`.idea/` | AI 助手/编辑器私有数据 |
| 构建产物 | `build/`、`android/build/`、`.dart_tool/` | 可随时重建 |

---

## 二、GitHub Actions 自动化流程（三套工作流）

提交到 `main` 后，以下流水线自动运行，可在仓库 **Actions** 页面查看：

| 工作流 | 触发时机 | 做什么 |
|--------|----------|--------|
| `CI` | push 到 main / PR 到 main | 静态分析（0 error 通过）→ 全量单元测试 → 构建 Web 与 Android APK（产物保留 14 天） |
| `Deploy (GitHub Pages)` | CI 成功后 | 把 Web 产物部署到 GitHub Pages（项目站点） |
| `Release` | 打 tag（`v*`） | 构建 Web + Android APK，创建 **GitHub Release** 供下载 |

### 如何发布一版 APK（重点）

打一个 `v` 开头的 tag 并推送，Release 工作流会自动构建并发布：

```bash
# 1. 在 main 分支打版本 tag（版本号自定，如 v1.0.0）
git tag v1.0.0
git push origin v1.0.0

# 2. 等待 Actions → Release 工作流跑完（约 10~15 分钟）

# 3. 在仓库页面右侧的 Releases 里下载：
#    - app-release.apk          → Android 安装包（直接安装）
#    - web-build.zip            → Web 站点包（Pages 已自动部署，无需手动下载）
```

> 也可改用 `git push origin main && git tag v1.0.0 && git push origin v1.0.0` 一步到位。
> 更新版本号后重新打新 tag（如 `v1.0.1`）即可再次发布。

---

## 三、GitHub Secrets / Variables 配置表

仓库 **Settings → Secrets and variables → Actions** 中配置：

| 名称 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `DASHSCOPE_API_KEY` | Secret | 否 | 阿里云百炼 API Key。未配置时 App 自动退回本地 NLP + 设备端识别，功能仍完整 |
| `DASHSCOPE_BASE_URL` | Secret | 否 | 请求基址，未配置用默认私有 MaaS 端点 |
| `KEYSTORE_BASE64` | Secret | 否 | Android 正式签名（base64 编码的 .jks）。**未配置时自动用 debug 签名**，安装包可直接安装，但无法上架应用商店 |
| `KEYSTORE_PASSWORD` | Secret | 否 | 签名库密码 |
| `KEY_ALIAS` | Secret | 否 | 签名别名 |
| `KEY_PASSWORD` | Secret | 否 | 签名密码 |
| `IOS_BUILD_ENABLED` | **Variable** | 否 | 设为 `true` 启用 iOS 构建（见第五节） |

> 在 Actions 中 `--dart-define` 传入的密钥会**打进 APK/Web 产物**，仅适合 Demo/内测；
> 生产环境应改为后端代理持有密钥（源码中的安全提示同理）。

---

## 四、本地构建

```bash
# 前置：Flutter 3.44.x stable + Android SDK（compileSdk 37）
flutter pub get

# 构建 Android 安装包（输出 build/app/outputs/flutter-apk/）
flutter build apk --release

# 构建 Web（输出 build/web/）
flutter build web --release

# 全量测试 + 静态分析（合入 main 前必须本地全过）
flutter test
flutter analyze
```

---

## 五、iOS 可以打包吗？（结论：可以，但有前置条件）

**结论：能打包，但真机安装/上架需要 Apple 开发者账号与签名材料。**

### 5.1 三种情况对照

| 场景 | 需要什么 | 产物 | 能否装到真机 |
|------|----------|------|--------------|
| 模拟器验证 | 免费 Apple ID | `flutter build ios --simulator` | 否（仅模拟器） |
| 无签名构建 | 免费 Apple ID | `flutter build ios --release --no-codesign`（CI 已内置，产出 Runner.app 仅用于验证） | 否 |
| **真机安装 / TestFlight / App Store** | **Apple Developer Program 账号（99 美元/年）+ 证书 + 描述文件** | `.ipa` | ✅ |

### 5.2 真机打包需要配置的环境变量（仓库 Secrets）

CI 的 `Release` 工作流已内置可选 iOS 任务（默认关闭），启用步骤：

1. **购买/加入 Apple Developer Program**（99 美元/年，个人即可）。
2. 在 Apple Developer 后台生成：
   - **Distribution 证书**（.p12 导出，base64 编码）
   - **Ad Hoc / App Store 描述文件**（.mobileprovision，含你的设备 UDID）
3. 在仓库 **Settings → Secrets** 配置：

| Secret 名称 | 内容 |
|-------------|------|
| `IOS_BUILD_ENABLED`（用 **Variables**） | `true` |
| `APPLE_TEAM_ID` | 开发者团队 ID（Apple 后台可见） |
| `APPLE_ID` | Apple 开发者账号邮箱 |
| `APPLE_APP_SPECIFIC_PASSWORD` | 在 appleid.apple.com 生成的「App 专用密码」 |
| `IOS_DIST_CERT_BASE64` | Distribution 证书 .p12 的 base64 |
| `IOS_DIST_CERT_PASSWORD` | .p12 密码 |
| `IOS_PROVISIONING_PROFILE_BASE64` | 描述文件 .mobileprovision 的 base64 |

> 未配置以上材料时，iOS 任务默认不运行，不影响 Android 发布。
> 仅打 `--no-codesign` 包用于自测时，只需把 `IOS_BUILD_ENABLED` 设为 `true` 即可，
> 但该产物**无法安装到真机**。

### 5.3 本地真机打包（有账号后）

```bash
# 1. Xcode 中配置 Team 与签名（Runner target）
open ios/Runner.xcworkspace

# 2. 构建 ipa
flutter build ipa --release

# 3. 产物在 build/ios/ipa/*.ipa，可用 Apple Configurator 安装或上传 App Store Connect
```

---

## 六、私密信息管理（红线）

1. **`lib/config/secrets.dart` 永不入库**：首次克隆后手动创建（可复制
   `lib/config/secrets.dart.example` 填真实值）；其真实 Key 只存在于你的本地。
2. **CI 用 `--dart-define` 注入密钥**，仓库 Secrets 仅存在于 GitHub 加密存储，
   不出现在日志（注意不要在 workflow 里 `echo ${{ secrets.X }}` 打印）。
3. **Android 签名文件**（`.jks`、`key.properties`）不入库；正式签名密钥丢失
   将无法更新已发布应用，务必离线备份。
4. 若发现某文件已误入库，立即从跟踪中移除并**轮换其中的密钥**（泄露即作废）。
