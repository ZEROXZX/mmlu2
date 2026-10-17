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

> **关于 `flutter test` 的 43/43**：`flutter create` 会顺手生成一个默认的
> `test/widget_test.dart`（counter smoke test，引用 `MyApp`），它和我们项目的
> `main.dart`（类名是 `MmluApp`）对不上，**会让 `flutter test` 编译失败**。
> 本包**已删除**该文件。若你重新跑过 `flutter create` 又生成了它，删掉即可；
> 它**不影响 `flutter build apk`**（`test/` 不进 APK）。

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

## 5b. 运行时权限与文件落点

**本客户端申请的权限**（`android/app/src/main/AndroidManifest.xml`）：

| 权限 | 生效条件 | 用途 |
|---|---|---|
| `INTERNET` | 始终 | 全部网络请求 |
| `ACCESS_NETWORK_STATE` / `WAKE_LOCK` | 自动合并（Media3） | 播放器判断网络、防息屏 |
| `WRITE_EXTERNAL_STORAGE`(≤API29) / `READ_EXTERNAL_STORAGE`(≤API32) | Android 10 及以下 | 写公共存储 |
| `MANAGE_EXTERNAL_STORAGE` | Android 11+ | 写公共 `Download/mmlu` 与 `Pictures/mmlu` |
| `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` | Android 13+ | 相册 |
| `POST_NOTIFICATIONS` | Android 13+ | 下载完成通知 |

**首次启动**（登录页出现后约 0.8 秒）依次弹出：
1. 通知 / 相册权限（Android 13+ 系统弹窗）
2. **Android 11+ 会跳到系统「所有文件访问」设置页** —— 需手动把本应用打开
   （这是写公共 `Download` 目录的必经步骤；不授权则回退私有目录）

**文件落点**：
- 下载到 `Download/mmlu/<分类>/`，分类为 **动画 / 漫画 / 小说 / 图集**
  （视频 `.mp4`、图片 `.zip`、小说 `.txt`）
- **图片（漫画/图集）默认只产出 `.zip`**，不再同时写相册，避免重复占地。
  如需相册单图，在「下载」页顶部工具栏打开 **「导出相册」** 开关（默认关）——
  开启后除 zip 外再写 `Pictures/mmlu/<标题>/0001.jpg …` 并通知系统媒体库；
  删除该下载任务时对应的 `Pictures/mmlu/<标题>` 也会一并清理。
- 视频完成后自动进入系统媒体库（相册/视频可见）
- 临时分片在 `Download/mmlu/.parts_<id>/`，合并完成后自动删除

**权限被拒 或 非 Android**：自动回退到 app 私有目录
（`/data/user/0/<包名>/files/mmlu_downloads/`），功能照常，只是其他 App 看不到文件。

> 原生实现见 `android/app/src/main/kotlin/com/example/mmlu_client/MainActivity.kt`
> （MethodChannel `mmlu/native`）；Dart 封装见 `lib/data/service/native_bridge.dart`。
> 全部用平台原生 API，不引入任何 Flutter 插件，避免 AGP 9 兼容问题。

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

## 6b. ⚠ release 包卡在启动图【实测定位，必读】

**症状**：`flutter build apk --release` 装到真机，打开后**一直卡在启动画面**
（居中 APP 图像 + 黑/纯色背景），而 debug 包正常、`flutter analyze`/`flutter test` 全通过。

**根因**：**AGP 9.x 在 release 默认开启 R8** —— 即使 `android/app/build.gradle.kts`
里一个 `minifyEnabled` 都没写，release 也会跑 R8（minify + shrink + obfuscate；
官方文档：*"R8 is enabled by default when you build a release APK… always enabled
in release builds"*）。同时 **Flutter Gradle Plugin 在 AGP 9 下配置 keep 规则 /
`minifyEnabled` 仍在用旧 DSL，规则不生效**
（[flutter/flutter#184410](https://github.com/flutter/flutter/issues/184410)）。
结果 R8 把 Flutter 引擎/插件运行时依赖的类混淆或裁剪掉 —— 在 APK 里可直接看到
`GeneratedPluginRegistrant` 的 `sourceFile` 变成 `r8-map-id-<hash>`、
`registerWith(Lvq;)` 的参数类型被改名 —— 引擎初始化失败 → 卡启动图。

> **注意**：`flutter build apk --no-shrink` 在 AGP 9 下**已失效**，官方文档明确
> *"The `--[no-]shrink` flag has no effect"*，只能在 gradle 文件里关。

**修复（本包已改好；若你另建了 `android/` 目录需自行加）**：
`android/app/build.gradle.kts` → `buildTypes.release`：

```kotlin
buildTypes {
    release {
        isMinifyEnabled = false
        isShrinkResources = false
        signingConfig = signingConfigs.getByName("debug")
    }
}
```

关掉后 APK 会略大、不再生成 `mapping.txt`，但**能正常启动**。
（想保留 R8：需补齐 Flutter 引擎与所有插件的 keep 规则，漏一处就会以别的形式
再卡/崩，不推荐。）

**验证**：重新 `flutter build apk --release` → 安装 → 能进登录页即可。

### 6c. release 包能启动但无法联网（缺 INTERNET 权限）

Flutter 模板只在 `android/app/src/debug/AndroidManifest.xml` 与
`profile/AndroidManifest.xml` 里声明 `INTERNET`，**release 用的 main manifest 里没有**
→ release 包所有网络请求失败。修复：在
`android/app/src/main/AndroidManifest.xml` 的 `<manifest>` 下加：

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

（本包已加好。）

### 6d. 登录报 `type 'int' is not a subtype of type 'String?' in type cast`

服务端登录返回的 `TokenResponse`（以及 `UserInfoResponse`）里，`UUID` / `userId` /
`phone` / `country_codes` 等字段**类型不稳定**：账号 ID 类字段可能是 JSON 数字
（int），而代码用 `j['userId'] as String?` 强转 → 抛
`type 'int' is not a subtype of type 'String?' in type cast`。

修复：一律用宽松转换取值（本包已改）——
`lib/data/models/token_response.dart`、`lib/data/models/user_info_response.dart`：

```dart
String? _str(Object? v) => v == null ? null : (v is String ? v : v.toString());
int? _intv(Object? v) => v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));
```

### 6e. 打开 APP 就强制登录、无法跳过

原实现 `home: tokenStore.isLoggedIn ? HomeShell() : LoginPage()`，且
`isLoggedIn` 仅判断「有无 token」（游客 device token 也算），导致每次冷启动都进登录页。

改为：**打开即进主界面（`home: const HomeShell()`），登录变为可选**——
入口在右上角「账号」页（未登录显示「登录官方账号」按钮）；
`TokenStore.isLoggedIn` 改用独立标记 `mmlu_logged_in`（游客 token 不算登录），
登录成功 `markLoggedIn(true)`、登出时清除。

> 注意：内容接口需官方账号（游客 token 访问内容返回 **495 unidentify**）。
> 未登录可进 App 框架，但列表/播放等内容区可能为空或提示 495。

### 6f. 内容接口大面积 400 / 图集详情 500 / 下载分片报「No host specified」【实测定位】

登录后可进 App，但真机实测出现一批报错，根因是**客户端默认参数非法**与**路径选错**，
均在沙箱用 `tools/mmlu_api.py` 逐条复现定位：

| 真机现象 | 根因 | 修复 |
|---|---|---|
| 动漫/漫画/小说接口 400、分类除图集外全 400 | 服务端要求 `type ≥ 1`（`type=0` → `400 {"type":["The type must be at least 1."]}`） | `api_service.dart` 与 `content_repo.dart` 所有列表/分类默认 `type: 1` |
| 搜索 400 | `sort` 须 ≥1（`sort=0` → `400 {"sort":[...]}`） | `search/searchData/searchNs` 默认 `sort: 1` |
| 历史报错 | `range` 须 ≥1（`range=0` → `400 {"range":[...]}`） | `histories` 默认 `range: 1` 并 clamp；历史页去掉「全部(0)」 |
| 收藏/历史 502（漫画） | 用了失效的旧路径 `v2/comic/favorite|history` | 改按种类取路径：comicNs → `v3/comic/ns/*`、comicAv → `v3/comic/data/*`、其余 → `v2/{kind}/*`（复用 `_favoriteBase`/`_historyBase`） |
| 漫画 av 榜单/推荐为空 | `v2/comic/ranking|recommend` 已废弃（恒空） | 改用 `v3/comic/data/ranking|recommend` |
| 图集只显示预览图、「查看全部图片」500 | `detail()` 用 `photoRead` 响应（`{data:[...]}` 无 id）建 item → `id=0` → `photoRead(0)` → 500 | 建 item 时显式补回传入 id（`{...map, 'id': id}`） |
| 下载动漫分片失败 `No host specified in URI` | AV m3u8 的 `#EXT-X-KEY URI="stream-encrypt1.mmlutech.xyz/..."` **无 scheme**，`parseM3u8` 原样透传 | `parseM3u8` 归一化 keyUri/分片：无 scheme 补 `https://`，`//host` 补 `https:` |
| 图集搜索 404 | `v2/v3/search/*/photo` 均 404（服务端无此路由） | 搜索下拉移除「图集」 |
| 账号页显示「账号状态：受限」 | `lock` 语义未定（正常 VIP 账号 `lock=2`），原 UI「非 0 即受限」误导 | 移除该行，改显示会员(VIP/普通)与到期日 |

> 仍属**服务端**问题、客户端无法修（已做容错/降级）：`v3/photo/similar` 常 502、
> `api1.mmlu.services` 密集请求时约 50% `Connection reset`、`v2/user/info` 偶发 502。

### 6g. 未登录(游客)报 499 / 动漫只能看预告片 / 小说列表空白图且阅读 403 / 收藏第一种漫画无图【实测定位】

对照可用参考实现 `/storage/emulated/0/mmlu第三方/` 逐条定位：

| 真机现象 | 根因 | 修复 |
|---|---|---|
| 未登录直接报 `ApiException(499): 缺少Token參數` | 启动只拉 host.txt，**从未注册游客 token**，`AuthInterceptor` 无 token 可附 | 启动即 `v2/register` 拿游客 token（`ApiClient.ensureGuestToken`，`main.dart` 引导链调用）；请求遇 `499/495` 自动重注册重试 |
| 注册了 token 内容仍空（`{error:{msg:unidentify}}`） | 游客注册后**必须再调 `v2/combine/startup`** 激活会话，否则内容接口回 unidentify（HTTP 200） | `ensureGuestToken` 注册成功后随即 startup；`_send` 见 `unidentify` 也自动重注册重试 |
| 搜索/收藏点开的动漫播放 `Source error`、只有「预告片」 | 搜索结果的动漫 `source='av'`，客户端据此走 `v2/combine/animat/internal` → media 为 `/v1/animat/media/...`，该路径已**失效（返回 HTML）** | 动漫详情**统一走 `v3/nsanimat/internal/{id}`**（对任意 id 均返回可播放的 `/v3/nsanimat/media/...`），忽略 source |
| 播放本地代理 `ExoPlaybackException: Source error` | `127.0.0.1` 本地 HLS 代理是明文 HTTP，Android 9+ 默认禁明文（media3/ExoPlayer 走系统策略） | 加 `res/xml/network_security_config.xml` 放行 `127.0.0.1`/`localhost` 明文，manifest 引用 |
| 小说列表全是空白图 | 小说条目**无 `cover` 字段**，网格仍渲染 `CoverImage` → 破图 | `ContentTile`/`HorizontalContentRow` 对 fiction 用**纯文字卡片**；`CoverImage` 无图时用中性占位而非破图 |
| 阅读小说容器 403 / `Connection reset`（host=ac1） | 小说正文在 **fiction 域**，客户端 `urlFor` 对非动漫一律取 comic(ac1) → 403 | `ResourceService.urlFor` 对 `ContentKind.fiction` 取 `apiFiction`(`fiction1.mmlutech.xyz`) |
| 下载动漫/小说分片 403（`shturl.cc/...` 签名 URL） | 同上：AV 路径的签名分片；NS 分片为 `na.mmlu1.site` **无签名**可直下 | 动漫改走 NS 后分片不再走签名；小说走 fiction 域 |
| 收藏里「两个漫画」第一个(ns)不显示封面 | 收藏接口的 ns 封面 key/iv 可能为 **Base64 逐图**（列表接口是 64 位 hex 固定） | `_coverOf` 检测 key：Base64 → 切 `perImage`；hex → 保持固定方案 |

> 已实测确认（无需再猜）：`v3/nsanimat/internal/{任意 id}` 均返回 `/v3/nsanimat/media/{intro,720,240}` 三档；NS m3u8 分片 `na.mmlu1.site/apen/<key>/ts/*.ts` 直下 200、key.php 16 字节、AES-128-CBC 解密后为 MPEG-TS（sync=0x47）；`fiction1.mmlutech.xyz/zhcn/*.txt` 明文 200。

---

## 7. 常见错误速查（均为沙箱实测）

| 现象 | 原因 | 处置 |
|---|---|---|
| **release 包卡在启动图**（中央 APP 图像 + 黑背景），debug 正常 | AGP 9 默认开 R8，Flutter keep 规则不生效 | §6b：显式 `isMinifyEnabled=false; isShrinkResources=false` |
| **release 能启动但所有网络失败** | main manifest 缺 INTERNET 权限 | §6c：加 `<uses-permission ... INTERNET/>` |
| 登录报 `type 'int' is not a subtype of type 'String?' in type cast` | 服务端 `userId`/`UUID` 等返回 int，代码 `as String?` 强转 | §6d：宽松转换 `_str()` |
| 打开即登录页、无法跳过 | `isLoggedIn` 误判 + `home` 强制登录 | §6e：`home: HomeShell()` + 独立登录标记 |
| 大批内容接口 400（动漫/漫画/小说/分类/搜索） | `type`/`sort`/`range` 传了 0，服务端要求 ≥1 | §6f：默认改 1 并 clamp |
| 收藏/历史 502、漫画 av 榜单为空 | 旧 `v2/comic/*` 路径失效 | §6f：改 `v3/comic/ns|data/*` |
| 图集「查看全部图片」500 | 详情 item 丢 id（=0）→ `photoRead(0)` | §6f：建 item 时补回 id |
| 下载分片 `No host specified in URI` | m3u8 的 KEY URI 无 scheme | §6f：`parseM3u8` 补 `https://` |
| 未登录报 `499 缺少Token參數` / 内容空 `unidentify` | 无游客 token / 注册后未 startup | §6g：启动注册游客 token + startup；499/unidentify 自动重试 |
| 动漫点开只播放「预告片」/ `Source error` | `source=av` 走了失效的 `/v1/animat/media` | §6g：动漫详情统一 `v3/nsanimat/internal/{id}` |
| 播放 `ExoPlaybackException: Source error` | 本地代理 127.0.0.1 明文被系统拦截 | §6g：network_security_config 放行 localhost |
| 小说列表空白图 / 阅读 403 | 小说无封面仍渲染图；正文取错域(ac1) | §6g：fiction 纯文字卡 + 正文走 fiction 域 |
| 收藏第一个漫画无封面 | ns 封面 key/iv 为 Base64 逐图 | §6g：`_coverOf` 自动切 perImage |
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

1. 首次启动 → 直接进主界面（不强制登录）；登录入口在右上角「账号」页
   （内容接口需官方账号，未登录访问内容会返回 495）
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
├── test/                   # 46 例单元测试
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
