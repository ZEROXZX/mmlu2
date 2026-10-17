# mmlu_client — Android 打包教程（实测版）

> 目标：把本源码打成可安装 APK。
> 源码状态：`flutter analyze` = 0 issues，`flutter test` = 43/43 通过；
> 本包源码在 **aarch64 沙箱**内未能跑完最后一步（AAPT2 架构问题，见 §6），
> 在 **x86_64 主机**上按本教程可直接完成打包。

---

## 1. 环境要求

| 项 | 版本 / 说明 |
|---|---|
| Flutter | 3.47.x（含 Dart 3.13.x，任意渠道） |
| JDK | **17+**（实测 OpenJDK 17.0.20 可用；遇 Gradle 兼容提示可换 21） |
| Android SDK | `platform-tools`、`platforms;android-36`（构建会自动补 35）、`build-tools;36.0.0` |
| NDK | `28.2.13676358`（AGP 首次构建自动下载，约 1GB；也可手动 sdkmanager 装） |
| CPU | **x86_64（推荐）**；ARM64 Linux 有额外坑，见 §6 |
| 磁盘 | 约 6GB（SDK + NDK + Gradle 缓存） |

纯命令行装环境（Ubuntu 示例）：

```bash
sudo apt install -y openjdk-17-jdk-headless unzip zip

# Android SDK 命令行工具
mkdir -p /opt/android-sdk/cmdline-tools
curl -L -o /tmp/cmdline.zip \
  https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip -q /tmp/cmdline.zip -d /opt/android-sdk/cmdline-tools
mv /opt/android-sdk/cmdline-tools/cmdline-tools /opt/android-sdk/cmdline-tools/latest

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64   # 按本机 java 路径
export ANDROID_HOME=/opt/android-sdk
yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --sdk_root=$ANDROID_HOME --licenses
$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --sdk_root=$ANDROID_HOME \
  "platform-tools" "platforms;android-36" "build-tools;36.0.0"
```

> 使用 Android Studio 的话，第 3 节的 SDK 装好即可，其余相同。

---

## 2. 解压与本机路径

```bash
unzip mmlu_client_src_20261017.zip -d mmlu_client
cd mmlu_client

export ANDROID_HOME=/你的/android-sdk
export FLUTTER=你的/flutter/bin            # 加入 PATH
export PUB_CACHE=你的.pub-cache            # 可选

# local.properties 是本机路径，不随包分发，需自己写：
cat > android/local.properties <<EOF
flutter.sdk=$(dirname $(dirname $(readlink -f $(which flutter))))
sdk.dir=$ANDROID_HOME
EOF

flutter pub get
```

---

## 3. 网络与镜像（★ 受限网络必做）

沙箱实测：`maven.google.com`、`services.gradle.org`、`downloads.gradle.org`
直连超时；`dl.google.com`、`repo.maven.apache.org`、腾讯/阿里镜像可用。

**本包已预配置**（解压后无需再改）：

- `android/gradle/wrapper/gradle-wrapper.properties`
  → `distributionUrl` = 腾讯镜像 `mirrors.cloud.tencent.com/gradle/gradle-9.3.1-bin.zip`
- `android/settings.gradle.kts`、`android/build.gradle.kts`
  → `google()` 已替换为 `maven("https://dl.google.com/dl/android/maven2")`

**你还要改 Flutter SDK 内的 2 处**（否则构建 flutter_tools 时仍会连 maven.google.com）：

```bash
FL=$(dirname $(dirname $(readlink -f $(which flutter))))
sed -i 's|google()|maven("https://dl.google.com/dl/android/maven2")|g' \
  "$FL/packages/flutter_tools/gradle/settings.gradle.kts" \
  "$FL/packages/flutter_tools/gradle/resolve_dependencies.gradle.kts"
```

Flutter 引擎 / 依赖下载慢时（Google 官方中国镜像）：

```bash
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn
```

**还原官方源**（网络直连 Google 时可选）：把上述 `maven("https://dl.google.com/dl/android/maven2")`
改回 `google()`；`distributionUrl` 改回
`https://services.gradle.org/distributions/gradle-9.3.1-all.zip`。

---

## 4. 构建

```bash
flutter pub get
flutter analyze           # 应输出 "No issues found"
flutter test              # 应 43/43 All tests passed

flutter build apk --debug          # 快速验证
flutter build apk --release        # 正式包
# 产物：
#   build/app/outputs/flutter-apk/app-debug.apk
#   build/app/outputs/flutter-apk/app-release.apk

# 只要 arm64（更快、包更小）：
flutter build apk --release --target-platform=android-arm64
```

首次构建耗时较长（下 Gradle + AGP + Kotlin + NDK，约 5–20 分钟）。

---

## 5. Release 签名

模板 `android/app/build.gradle.kts` 当前 release 用 **debug 签名**
（能装能跑，但不适合分发/上架）。正式签名：

```bash
keytool -genkey -v -keystore ~/mmlu.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias mmlu
```

新建 `android/key.properties`（已被 .gitignore 忽略，勿外发）：

```properties
storePassword=你的
keyPassword=你的
keyAlias=mmlu
storeFile=/绝对路径/mmlu.jks
```

`android/app/build.gradle.kts` 内（在 `android { ... }` 中加）：

```kotlin
signingConfigs {
    create("release") {
        val props = java.util.Properties()
        rootProject.file("key.properties").inputStream().use { props.load(it) }
        storeFile = file(props.getProperty("storeFile"))
        storePassword = props.getProperty("storePassword")
        keyAlias = props.getProperty("keyAlias")
        keyPassword = props.getProperty("keyPassword")
    }
}
```

并把 `buildTypes.release.signingConfig` 改为
`signingConfigs.getByName("release")`。

---

## 6. ⚠ ARM64 (aarch64) 主机的坑【实测踩坑记录】

现象（Gradle 跑 10+ 分钟、依赖全下完后失败）：

```
> Failed to transform appcompat-1.1.0.aar ...
   > AAPT2 aapt2-9.1.0-14792394-linux Daemon #0: Daemon startup failed
Gradle build failed due to Java/Gradle incompatibility.
The Java version used for the build is 17.0.20, which is incompatible ...
```

根因：AGP 自带的 `aapt2-*-linux.jar` 解出的二进制是
**`ELF 64-bit x86-64`**，在 `aarch64` 主机上
`cannot execute: required file not found`（缺 `/lib64/ld-linux-x86-64.so.2`）。
（最后那句 Java 版本提示是**次要噪音**，真正原因就是 AAPT2 架构。）

处置（按优先级）：

1. **在 x86_64 机器上构建**（推荐，一劳永逸）。
   macOS Apple Silicon 不受影响（AGP 提供 darwin-aarch64 的 aapt2 / Rosetta 2）。
2. **Linux ARM64 + 有 root**：用 qemu-user 透明模拟 x86_64：

   ```bash
   sudo apt install -y qemu-user-static libc6-amd64-cross
   sudo mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
   sudo update-binfmts --enable qemu-x86_64
   export QEMU_LD_PREFIX=/usr/x86_64-linux-gnu    # 让 Gradle/JVM 的子进程继承
   flutter build apk --debug
   ```

   验证是否生效：

   ```bash
   A=$(find ~/.gradle/caches -name 'aapt2-*-linux.jar' | head -1)
   unzip -p "$A" aapt2 > /tmp/aapt2 && chmod +x /tmp/aapt2
   /tmp/aapt2 version     # 能打印版本号即通过
   ```

3. **无特权容器/沙箱**（挂不上 binfmt_misc、无法注册 qemu）：方案 2 不可用，
   只能换 x86_64 主机。单独改 `android.aapt2FromMavenOverride` 不够——
   SDK `build-tools/36.0.0/` 下的 `zipalign`/`aidl` 等同样是 x86_64。

---

## 7. 常见错误速查（均为沙箱实测）

| 现象 | 原因 | 处置 |
|---|---|---|
| `java.net.ConnectException ... services.gradle.org`（Gradle wrapper 卡住） | 官方分发包域名不通/重定向到不通的 CDN | §3 腾讯镜像 distributionUrl（本包已配） |
| 下载中 `Connection reset`（大文件中途断） | 网络对大文件不稳 | 用 `wget -c`/`curl -C -` 断点续传下载到本地，distributionUrl 改 `file:/本机路径/gradle-9.3.1-bin.zip`（实测 137MB 成功） |
| `Could not resolve ... maven.google.com` / `google()` 超时 | Google Maven 不通 | §3 sed 替换（工程内 2 处本包已改；**Flutter SDK 内 2 处需自己改**） |
| `AAPT2 ... Daemon startup failed` | ARM64 主机 | §6 |
| `Execution failed for task ':app:processDebugResources'` | 上面两条的组合表现 | 看子错误逐条处置 |
| `License for package ... not accepted` | 未接受 SDK license | `yes \| sdkmanager --licenses` |
| Gradle `OutOfMemoryError` | daemon 内存超限 | `android/gradle.properties`：`org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=1G` |
| Flutter assets 下载慢 | storage.googleapis.com 慢 | `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`（本沙箱实测该镜像 200，引擎构件能下） |

---

## 8. 打包后的真机验证点

`flutter install -d <设备>` 或 `adb install -r app-release.apk`：

1. 首次启动 → 登录页（登录官方账号；沙箱实测 token 在其他设备登录会被 496 顶下线）
2. 首页 banner / 各分类列表
3. 详情页：分集合集（前篇+后篇并列）、**相似作品**（samelike）、系列可点
4. **播放**：直流播放（本地代理流播，起播即播）；顶栏「合集」可切集
5. **下载**：任务页进度/暂停/恢复/取消、并发数切换（1/2/4/8）、历史与三条链接
6. 离线：下载完成后再次进入播放页应自动播本地文件
7. 小说：单章下载 + 勾选多章下载；图集/漫画打包下载

> **FFmpeg（R1.5 转 MP4）**：`Mp4Converter` 默认调用 PATH 里的 `ffmpeg`
> （`lib/data/service/download_service.dart`）。Android 上需二选一：
> - 随包带 ffmpeg 可执行（放进 `android/app/src/main/assets/`，启动时解压到
>   `context.filesDir`，再 `Mp4Converter(ffmpegPath: <该路径>)`）；
> - 或改用 `ffmpeg_kit_flutter` 插件替换 `Mp4Converter`。
> 否则 TS→MP4 静默失败（下载分片仍保留，不影响其它功能）。

---

## 9. 包内结构速览

```
mmlu_client/
├── lib/                    # 全部 Dart 源码
│   ├── core/               #   加密、域名、网络、常量
│   ├── data/{api,models,repo,service}/
│   │   ├── api_service.dart        # 111 接口封装
│   │   ├── hls_proxy.dart          # ★ 直流播放本地代理
│   │   ├── download_task.dart      # ★ 下载任务状态机（暂停/恢复/取消/并发）
│   │   ├── stream_service.dart     # 分片拉取+解密+断点续传
│   │   └── download_service.dart   # FFmpeg 转码 / 产物目录
│   └── ui/pages/          # 首页/详情/播放器/阅读器/下载/历史/搜索/账号…
├── test/                   # 43 例单元测试
├── docs/
│   ├── PROTOCOL.md         # 完整协议逆向（鉴权/取流/解密/写操作/14 密钥）
│   ├── REQUIREMENTS.md     # 需求清单 + 实现进度
│   └── BUILD.md            # 本文
├── tools/mmlu_api.py       # 协议 Python 参考实现 + CLI（登录/下载/解密）
├── android/                # 打包配置（已配镜像，见 §3）
└── pubspec.yaml
```

**安全提醒**：源码包**不含** `.state.json`（实测 token 与账号凭据）与
`android/local.properties`、`key.properties`——这三样都在本机自建，勿提交、勿外发。
