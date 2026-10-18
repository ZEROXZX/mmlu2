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
| 搜索展示与点开**内容不符** / 点开 AV 项报 `ApiException(410): 资源无法存取` | AV 与 NS 是**两套 id 空间**：`source='av'` 的 id（如 14767）交给 `v3/nsanimat/internal` 会拿到**别的作品**或 **410** | 详情**按 source 路由**：`av`→`v2/combine/animat/internal`；`ns`/缺省 → `v3/nsanimat/internal`；410/404 互回退（`ContentRepo._animatDetail`） |
| AV 动漫播放 `Source error`（旧结论已纠正） | 早前误判 `/v1/animat/media` 已失效；实测**仍可用**：`/v1/animat/media/720/xxx.m3u8` 解密后为标准 HLS，分片为 `na.mmlu1.site/apen/<key>/ts/*.ts` **带实时签名**（`Signature=`/`Key-Pair-Id=`） | 详情按 source 走 v2 后 media 即该路径；**每次播放/下载重新拉 m3u8** 取新签名即可正常播放 |
| 播放本地代理 `ExoPlaybackException: Source error` | `127.0.0.1` 本地 HLS 代理是明文 HTTP，Android 9+ 默认禁明文（media3/ExoPlayer 走系统策略） | 加 `res/xml/network_security_config.xml` 放行 `127.0.0.1`/`localhost` 明文，manifest 引用 |
| 小说列表全是空白图 | 小说条目**无 `cover` 字段**，网格仍渲染 `CoverImage` → 破图 | `ContentTile`/`HorizontalContentRow` 对 fiction 用**纯文字卡片**；`CoverImage` 无图时用中性占位而非破图 |
| 阅读小说容器 403 / `Connection reset`（host=ac1） | 小说正文在 **fiction 域**，客户端 `urlFor` 对非动漫一律取 comic(ac1) → 403 | `ResourceService.urlFor` 对 `ContentKind.fiction` 取 `apiFiction`(`fiction1.mmlutech.xyz`) |
| 下载动漫/小说分片 403（签名 URL） | AV 分片是**署名 CloudFront URL**（`na.mmlu1.site/apen/...?Signature=...`），签名**随 m3u8 实时下发**，用旧签名/缓存 m3u8 会 403 | 下载前**重新拉一次 m3u8** 取新签名；小说走 fiction 域（`ResourceService.urlFor`） |
| 收藏里「两个漫画」第一个(ns)不显示封面 | 收藏接口的 ns 封面 key/iv 可能为 **Base64 逐图**（列表接口是 64 位 hex 固定） | `_coverOf` 检测 key：Base64 → 切 `perImage`；hex → 保持固定方案 |

> **更正（2026-10-17，fix7）**：`v3/nsanimat/internal/{id}` 只对 **NS id** 返回正确作品；对 **AV id**（如 14767）会返回**别的作品**或 **HTTP 410 `资源无法存取`**。AV 详情须用 `v2/combine/animat/internal/{id}`，媒体 `/v1/animat/media/...`（署名 CloudFront 分片，随 m3u8 实时下发）。
> 已实测确认：NS m3u8 分片 `na.mmlu1.site/apen/<key>/ts/*.ts` 直下 200、key.php 16 字节、AES-128-CBC 解密后为 MPEG-TS（len%188==0）；AV `GHOSTFATHER-0008` 同域同结构、有签名；`fiction1.mmlutech.xyz/zhcn/*.txt` 明文 200。

### 6h. 搜索点开内容不符 / 点开报 `ApiException(410)` / 详情缺「作品信息」/ 下载复制链接【实测定位，fix7】

搜索「鬼父」得到 `source='av'`、`id=14767`，但点开：
- `v3/nsanimat/internal/14767` → **别的作品**「【MMD】飞霄…」（HTTP 200，**静默串台**）；大量 AV id（1..25）→ **HTTP 410 `资源无法存取`**；
- `v2/combine/animat/internal/14767` → **正确**「鬼父 Rebuild…」，media `/v1/animat/media/...`。

| 真机现象 | 根因 | 修复 |
|---|---|---|
| 搜索展示与点开内容不符 / 点开报 `ApiException(410): 网络错误` | AV/NS 是**两套 id 空间**，详情没按 `source` 路由（统一走 v3/nsanimat） | `ContentRepo.detail` → `_animatDetail(id, source)`：`av`→`animatDetail`(v2/combine)、其余→`nsAnimatDetail`(v3/nsanimat)；**410/404 互相回退** |
| 详情页只有标题/图，缺描述信息 | 未展示 `summary` 里的系列/季/集数/时长/播放量等 | `detail_page` 新增「作品信息」区块（系列/季/集数/时长/播放量/发行/制作/来源/编号/发布时间/标签） |
| 下载后想拿「加密/密钥/解密后」链接 | 任务未保存三条 URL | `DownloadTask` 加 `encryptedUrl`/`keyUrl`/`decryptedUrl`，下载中就记录；下载页任务行与历史行均可「复制下载链接」（通用对话框，支持复制全部） |
| 图集/漫画「导出到相册」开关无效 | `_saveImagesToGallery` 定义后未调用（死代码） | `_runImages` 完成后按 `exportToGallery` 调用 |
| 下载产物文件名是一串 id（`12345.zip`），认不出内容 | 输出文件用 `${t.id}.<ext>` 命名 | 统一改用**作品名**：`<标题>.mp4/.zip/.txt`（`_safeName` 过滤 `\/:*?"<>|`、截断 60 字、空标题回退 id），`Download/mmlu/<分类>/` 下 |

> AV 链路可播（实测）：`/v1/animat/media/720/GHOSTFATHER-0008.m3u8` 解密后是标准 HLS；
> `key.php` 16 字节、分片 AES-128-CBC 解密后 `len%188==0`。分片带 `Signature`/`Key-Pair-Id`
> 但**随 m3u8 每次实时下发**，故播放/下载前必须重新拉 m3u8（客户端已如此）。
> `source` 缺省时按 NS 处理；参考实现 src4 `server.py:694` 对 anime 详情也恒走 v3，**同样会错，勿盲抄**。

### 6i. 复制链接入口不明显 / 动漫合集需分开下载 / 瞬时网络抖动 / 登录文案【fix8】

| 真机现象 | 根因 | 修复 |
|---|---|---|
| 「复制下载链接」找不到入口 | 任务行仅有个小图标、历史行要隐式点按整行 | 详情页与下载页**两处都有**：详情页下载按钮旁加「复制链接」（**下载前**即可取；分集行内亦有「复制下载链接」）；下载页任务行加**显式「复制下载链接」按钮**（带文字）、历史行 `trailing` 加链接按钮（与删除并列），`onTap` 保留 |
| 下载页只有在**下载完成后**才显示链接 | 三链接里「解密后链接」= 本地成品文件路径，需下载完才有 | 详情页「复制链接」**未下载时**：加密链接=m3u8、密钥链接=`key.php` keyUri、解密后链接=**本机串流代理地址** `http://127.0.0.1:端口/play.m3u8?m=...`（边下边播用）；下载完成后下载页该条改显示本地文件路径 |
| 动漫只能「一起下」，想分开选几集下 | 详情只有一个下载按钮（=整季入队） | `detail_page` 拆两个按钮：**`合集一起下载`**（全集入队）与 **`分开下载`**（勾选框多选分集，逐集独立任务，画质选一次） |
| 偶发网络抖动请求直接失败 | `_send` 只做 token 自愈，未对瞬时故障重试 | `_send` 对**连接/超时/空响应**退避重试（≤4 次，指数退避）；HTTP 错误不重试 |
| 小说正文某线路 403 / reset | 单 host 无兜底 | `ResourceService.urlsFor`/`getText`：fiction 域按 `MmluKeys.fictionFallbackHosts`（`fiction1.mmlutech.xyz` → `fiction1.mmlu4.site`）轮换 |
| 登录失败无明确提示（只 `ApiException(...)`） | 未解析服务端错误信封；且 200+错误信封会被误判为登录成功 | `ApiService.login` 无 token 即抛错；`extractApiMessage` 递归提取 `message/msg/error/errors/detail` 文案，登录页显示友好提示 |

> 复制链接对话框（共用组件 `lib/ui/widgets/download_links.dart` → `showDownloadLinks`）含**加密链接 / 解密密钥链接 / 解密后链接**三条，支持「复制全部」；任务任意状态均可查看（未开始下载时提示「暂无可用链接」）。
> 详情页入口：`_actions` 的「复制链接」按钮（`_copyLinks`）+ 分集行内链接图标（`_copyLinksForEpisode`）；动漫需先选分集/画质，取 `StreamService.buildM3u8Url`(加密) + 解析 m3u8 的 keyUri(密钥) + `HlsProxy.playUrl`(解密后本机地址)。
> **未借鉴**（评估后放弃）：参考实现 `ts2mp4.py` 的纯 Dart TS→MP4 重封装（本沙箱无 ffmpeg/ffprobe，无法验证位级输出，风险高）；Cloudflare 候选 IP 兜底（真机 DNS 正常，收益低）；收藏/历史多路径回退（现接口已稳定，收益低）。

---

### 6j. 动漫下载分片报 403 / 图集·漫画「复制链接」要 zip【fix9】

| 真机现象 | 根因 | 修复 |
|---|---|---|
| 动漫下载 `分片 0/291 · 0B · Bad state: 拉取失败: https://stream-encrypt1.mmlutech.xyz/apen/<avkey>/key.php?...`（**HTTP 403**） | host.txt 的 `stream[].tsurl`（`stream-encrypt1.mmlutech.xyz` / `stream-encrypt1.mmlu4.site`）被当作 `?host=` 传，服务端据此把 **AV** 的 `key.php` 与 `*.ts` 签在该域上；而该域对这两者**一律 403**（实测 `GHOSTFATHER-0008` key/分片均 403、110B 错误页）。`host=na.mmlu1.site` 时 key(16B)/分片(1.2MB) 均 **200** | `StreamService.buildM3u8Url` 新增 `_streamHost` 归一化：`?host=` 一律转 `na.mmlu1.site`（`stream-encrypt*` 与空值→`na.mmlu1.site`，其它可用主机保持原样）；`DomainStore.streamTsUrl` 默认值改 `na.mmlu1.site`。NS 端点本就忽略 `?host=`（恒回 `na.mmlu1.site`），不受影响 |
| 图集/漫画「复制链接」给出的是**单张首图**密文地址+密钥，非 zip | 服务端**无 zip 接口**，zip 是 App 本地解密后打包产物 | 详情页 `_copyLinks` 对图集/漫画改为**即时打包**：新增 `DownloadManager.packImages`（并行下载→解密→`Archive`+`ZipEncoder`→写 `Download/mmlu/<分类>/<标题>.zip`，不建任务/不发通知），完成后「解密后链接」= 该本地 **zip 路径**；期间弹「正在打包 zip…」进度框。小说仍是首章密文；动漫不变。**（fix11 起已回退：复制链接不再打包，见 §6l；`packImages` 改由「打包下载」按钮调用）** |

> 诊断脚本：`tools/probe_stream.py` / `tools/diag2.py`（对同一 m3u8 轮询 `host=na.mmlu1.site` 与 `host=stream-encrypt1.*`，直取 key/分片看状态码）。
> 契约测试：`test/stream_host_test.dart`（归一化）、`test/download_task_test.dart`（`packImages` 空页抛错）。

---

### 6k. 删记录连带删文件 / 无搜索历史 / 图集详情预览不显示【fix10】

| 真机现象 | 根因 | 修复 |
|---|---|---|
| 删除下载记录时，本地已下载文件也被删掉 | `DownloadManager.remove` 会 `deleteLocal(outputPath)` 并清 `*.ts/mp4/zip/txt` 与相册导出；历史区 `_deleteOne`/`_deleteMany` 也 `deleteLocal(filePath)` | **记录与文件解耦**：`remove` 只删任务 + R2 记录 + 临时分片目录 `.parts_<id>`，保留成品与相册；`_deleteOne`/`_deleteMany` 不再删文件；删除按钮 tooltip 改「删除记录（保留文件）」。要清空间请自行到文件管理器删 |
| 没有搜索历史功能 | 未持久化关键词 | 新增 `SearchHistoryStore`（本地 SharedPreferences，**无数量上限**、去重置顶、支持逐条删/清空）+ `AppContainer` 注入；搜索页空闲时显示历史 `InputChip`（点按重搜、✕ 删除、「清空」），搜索成功后写入 |
| 图集详情页预览图片不显示（但点「浏览图集」能正常看） | `v3/photo/read` 只返回 `{data:[{image_path,key,iv}...]}`，**无 id/name/cover** → 详情 item 无封面 → `CoverImage` 只显示占位图 | `ContentRepo.detail` 图集分支：补回传入 id，并以**首张图**（scheme=perImage）充当详情页预览封面；详情页标题用列表页传入的 `fallbackTitle` 兜底（`_title`），`浏览图集` 也带上标题 |

> 契约测试：`test/download_task_test.dart`（`remove` 保留成品文件）、`test/search_history_test.dart`（无上限/去重/删除）、`test/content_repo_animat_test.dart`（图集详情首图补封面 + 补 id）。

---

### 6l. 图集/漫画复制链接不再打包 zip / 小说详情去掉图片 / 启动强制授权【fix11】

| 真机现象 | 根因 | 修复 |
|---|---|---|
| 图集/漫画点「复制链接」会**先打包 zip**，很慢很麻烦 | fix9 把「复制链接」做成了即时打包 zip（下载→解密→压缩） | **回退**：`_copyLinks` 图集/漫画分支**不再打包**，直接弹三链接框——「加密链接」= 全部图片网络地址（逐行）、「解密密钥链接」= 逐图 `key/iv`（逐行）、无「解密后」。要 zip 请用「打包下载」按钮（`_downloadImagesZip` → `DownloadManager.packImages` 保留） |
| 小说详情页有一块**空白图片区**（无封面占位图） | 小说条目无 `cover`，详情页仍渲染 `CoverImage` 占位 | `_header` 对 `ContentKind.fiction` **不渲染图片区**（`if (kind != fiction) CoverImage(...)`） |
| 打开软件未申请权限、可自由使用 | 权限只在首帧后台静默申请 | 新增 `ui/pages/permission_gate.dart`：`MaterialApp.home = PermissionGate(child: HomeShell())`，启动即申请「存储/相册/通知」（Android 11+ 跳系统『所有文件访问』设置页），**未授权进入授权页、无法使用**；返回 App 自动重检；提供「去授权 / 已授权？重新检测」。`NativeBridge` 新增 `isAndroid`（非 Android 放行） |

> 契约测试：`test/download_task_test.dart`（`packImages` 空页抛错，打包能力仍保留）。

---

### 6m. 动漫收藏有概率无效 / 列表「更多」不会一直加载【fix12】

| 真机现象 | 根因 | 修复 |
|---|---|---|
| 动漫点「收藏」有概率无效（列表里看不到、状态对不上） | 动漫 **AV / NS 是两套 id 空间**：`addFavorite` 恒写 `v2/animat/favorite`（AV），而首页/分类的动画列表走的是 `v3/nsanimat/*`（NS）；且收藏列表只读 AV → NS 收藏写错源、列表也查不到。加上写操作**忽略 200 错误信封**，失败也照样翻按钮 → “静默无效” | ① 收藏增删**按 `source` 路由**（`ns`→`v3/nsanimat/favorite`，否则 `v2/animat/favorite`）；② 动漫收藏列表**合并 AV+NS 并去重**；③ `ContentRepo._ensureOk` 检测 `{error}` 信封并抛 `ApiException`，UI 弹「操作失败」不再静默；④ 详情页进入时 `_refreshFav` 拉收藏状态，令按钮初始态与实际一致 |
| 首页/分类点「更多」只显示一屏（约 20 条），下滑不再加载、来回都是那几条 | `ContentListPage` 一次性 `AsyncView` 拉一页，**无分页** | 重写为**滚动到底自动加载下一页**：`pages` 递增、按 `kind:id:source` 去重、本页不足或整页无新增即停止、首屏/追加失败分别给重试。首页与分类的「更多」均进入本页，故一并生效 |
| 搜索结果同样只显示一屏、下滑不再加载 | 搜索页 `SearchTab` 用 `AsyncView` 拉一页，**无分页** | 抽出可复用组件 `lib/ui/widgets/paginated_content.dart`（`PaginatedContentList`），`ContentListPage` 与 `SearchTab` 共用；搜索结果也**滚动到底自动加载下一页**，并支持**下拉刷新**（清空后从第 1 页重载）。搜索页以 `ValueKey(kind:query)` 重建，换词/换种类即从头加载 |

> 契约测试：`test/content_repo_animat_test.dart`（NS/AV 收藏路由、AV+NS 合并去重、error 信封抛 `ApiException`）。

---

### 6n. 客户端全量走查整改【fix14】

对 `lib/**` 全库走查后的 bug 修复（高危→低危）：

| 现象 / 隐患 | 根因 | 修复 |
|---|---|---|
| 下载**无 `#EXT-X-KEY` 的明文流**时崩溃（`Null check operator used on a null value`） | `downloadSegments` 里 `info.keyUri!` 强解包；`HlsProxy` 有兜底、下载路径没有 | `stream_service.dart`：`keyUri` 为空则 `key=null`，分片原样落盘 |
| 同一小说「单章下载」与「全本下载」互相覆盖（id 都是 `fiction_<id>`、文件名相同） | 任务 id / 产物名未区分下载作用域 | `DownloadTask` 新增 `suffix`；`addFiction`/`addImages` 新增 `scope`，非空时 id = `<kind>_<id>_<stableHash(scope)>`、文件名追加 `_<scope>` |
| 漫画「打包下载」**无差别下载全部分章**，且整本图片驻留内存易 OOM | 遍历 `d.chapters` 全下；`Archive` 先全量解密再一次性压包 | ① 多章漫画弹**章节勾选**；② 解密图片**逐页落临时文件**，再用 `ZipFileEncoder` **流式压包**（内存只驻留单张），打完删临时目录 |
| 下载合并中 `_getBytes` 每次 `new Dio()`（无连接复用） | 每次请求新建客户端 | 复用长驻 `_dio`（连接池） |
| 「清除已完成」后残留 `.parts_<id>` 临时目录 | `clearFinished` 不删临时分片目录 | `clearFinished` 追加删除 `_partDirOf(id)`（成品文件仍保留） |
| 小说下载弹窗文案显示「集」 | `_ChapterPickDialog` 默认 `unit:'集'` | 小说/漫画显式传 `unit:'章'` |
| 服务端错误信封 `{error:{...}}`（Map 型）只显示「network error」 | `api_client._message` 仅认 `error` 为 String | 改用 `extractApiMessage`（兼容 String / 嵌套 Map / errors 数组） |
| 详情页收藏态：第 21 条及以后的收藏被误判为「未收藏」 | `_refreshFav` 只取首页 | `ContentRepo.isFavorite`（分页遍历，**不只看首页**；动漫按 `source` 精确匹配） |
| 从详情页取消收藏返回后，收藏列表不刷新 | 收藏页无刷新机制 | `FavoritesTab` 加下拉刷新 + 从详情返回后自动重载 |
| 阅读页解密失败只看到破图、无法重试 | `_PageImage` 每次 build 新建 future（失败不重试） | `_PageImage` 改 Stateful（future 只建一次）+ 失败可点重试 |
| 阅读/封面/HLS 缓存无上限增长 | 静态缓存只增不减 | 阅读(>200)/封面(>500)/HLS(>256) 缓存超限清空 |
| 分页「重试」在 `setState` 内直接调异步 `_loadMore()` | setState 回调里触发异步副作用 | 先 `setState` 复位，再调 `_loadMore()` |

> 契约：`download_task_test.dart`（`scope` 生成不同 id）、`content_repo_animat_test.dart`（`isFavorite` 翻页 / source 精确匹配 / 不无限翻页）。

### 6o. 二次走查整改（详情页布局 / 代理明文流）【fix15】

fix14 后再次全库走查发现的遗留问题：

| 现象 / 隐患 | 根因 | 修复 |
|---|---|---|
| 详情页**整页红屏**（debug）/ 描述文字不显示（release） | `_header` 是 `Row > Expanded > Column > Expanded(desc)`，而该 Row 在 `ListView`（竖向无界）里 → `RenderFlex children have non-zero flex but incoming height constraints are unbounded`（抛错在 `assert` 内，release 下断言被剥，表现为描述被压成 0 高） | `detail_page.dart`：`_header` 的 `Row` 外套 `IntrinsicHeight`（高度收束到封面 148/150 高，描述按剩余高度裁切） |
| 播放**无 `#EXT-X-KEY` 的明文流**时代理返回 500、播不了 | `HlsProxy._serveSegment` 无条件 `_keyFor(info.keyUri)`，`keyUri` 为空时 `_keyFor` 抛 `StateError` | ① `StreamService.fetchSegment` 的 `key` 改为**可空**（null/空 → 原样返回分片，与下载路径一致）；② `_serveSegment` 仅在 `keyUri` 非空时取 key |
| 长期播放时 HLS `_infoCache` 只增不减（绕过上限） | `_servePlaylist` 预热时直接写 `_infoCache`，未过 `_infoFor` 的 >256 清空 | 抽 `_cacheInfo()`（带 >256 清空），预热与惰性解析共用 |
| 小说下载后大小显示为「字符数」而非字节（中文偏小） | `t.bytes = buf.length`（`StringBuffer.length` 是 UTF-16 码元数） | 落盘后取 `File(outPath).length()`（真实 UTF-8 字节）作 `bytes`/`totalBytes` |
| `packImages`（打包接口）与图片下载任务的临时目录同名 `.imgs_<id>` | 两者都用 `.imgs_$id` | `packImages` 临时目录改 `.imgs_pack_<id>`，避免同 id 并发冲突 |
| 分片已全部就位时仍白拉一次 key.php | `downloadSegments` 先取 key 再算 pending | 先算 pending，全就位直接返回，仅在确有缺片时才取 key |
| 图集详情页显示「收藏」按钮，点了必失败 | 图集无收藏接口（`v2/photo/favorite` 404），仍渲染按钮并请求 | `_actions` 对 photo **不渲染收藏按钮**，`_refreshFav` 对 photo 直接 return（不再发无效请求） |
| 动漫下载成品默认是 `.ts`（沙箱无 ffmpeg 时降级） | 转码用 `Process.run('ffmpeg')`，包内未附带 ffmpeg 二进制 | 改用 `ffmpeg_kit_flutter` 无损 remux（`-c copy`），失败回退重编码。仍要求真机有可用 ffmpegKit 运行时（aarch64 对应 native lib） |

> 契约：`stream_segment_test.dart`（`fetchSegment`：key 为 null/空 → 原样返回；有 key → AES-128-CBC 解密）。


## 6p. 第三轮走查（播放/流解析/小优化）【fix17 补充】

第三轮「再检测一遍」后记录：

| 现象 / 隐患 | 根因 | 处理 |
|---|---|---|
| 播放报 `ExoPlaybackException: Source error`（直流本地代理 `http://127.0.0.1:<port>/play.m3u8`） | Android 9+ 禁止明文 HTTP，media3/ExoPlayer 未放行 127.0.0.1 | `AndroidManifest.xml` 加 `android:networkSecurityConfig="@xml/network_security_config"`；`res/xml/network_security_config.xml` 放行 `127.0.0.1`、`localhost`。已修复。 |
| `parseM3u8` 未处理 `#EXT-X-MAP` 与 `#EXT-X-BYTERANGE` | 部分 fMP4/分片按字节范围切分的 m3u8 不常见；当前业务以 TS 分片为主 | **保留现状**（不修改实现）。如真机遇到此类清单导致首帧/分片异常再按需补全（保持向后兼容）。 |
| `ResourceService.fetchAndDecryptHostTxt()` 每次 `new Dio()` | 无连接复用必要，微优化 | 可选：改用静态 `_dioHost` 重用连接池。行为不变，未修改。 |
| `CoverImage` 在 ScrollView rebuild 时反复创建 future（Stateless 版） | 父级 rebuild 触发 `_load()` 新建 future | 改为 **StatefulWidget**：`_future` 只在 `initState` 创建，避免滚动闪烁。已修复。 |

> 注：`probe_stream.py` 因强制登出/缺 token 暂不可用；`diag2.py` 可自行取 guest token 用于 API 实测。

## 6q. 下载记录显示名与文件名一致【fix18】

历史记录（下载页）原先显示 `r.title`，导致「压缩包名称与显示名称不符」。
改为优先展示**文件名去后缀**（如 `题名.zip` → `题名`）。

| 现象 | 根因 | 修复 |
|---|---|---|
| 下载图集/漫画后，下载页历史记录的标题与实际文件名（`_safeName(title,id)[_scope].zip`）不一致 | 历史记录直接用 `r.title`（作品原始标题）展示 | `downloads_page.dart`：历史条目标题改为 `r.filePath` 取文件名去扩展名，失败回退 `r.title`。 |

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
| 搜索展示与点开动漫内容不符 / 点开 `ApiException(410) 资源无法存取` | AV/NS 两套 id 空间，详情未按 `source` 路由 | §6h：详情**按 source 路由**（av→`v2/combine/animat`，ns→`v3/nsanimat`），410/404 互相回退 |
| 下载页找不到「复制链接」入口 / 动漫想分开选集下载 | 入口隐式、只有全集按钮 | §6i：任务行显式「复制下载链接」按钮；详情拆「合集一起下载 / 分开下载」 |
| 偶发网络抖动请求直接失败 | `_send` 未对瞬时故障重试 | §6i：连接/超时/空响应退避重试（≤4 次） |
| 登录失败无明确提示 | 未解析错误信封，200 信封被误判成功 | §6i：`extractApiMessage` + 无 token 抛错 |
| 动漫下载分片/密钥 **403**（URL 在 `stream-encrypt1.*`） | `?host=` 用了 host.txt 的 `tsurl`（该域对 AV 的 key/分片一律 403） | §6j：`buildM3u8Url` 归一化 `?host=na.mmlu1.site` |
| 图集/漫画「复制链接」给的是单图而非 zip | 复制时未打包 | §6j：**（fix11 已回退，见下行）** 详情页复制链接即时打包为本地 zip 并给出路径 |
| 图集/漫画点「复制链接」要等打包 zip，太麻烦 | fix9 把复制链接做成了即时打包 | §6l：复制链接**不再打包**，直接给全部图片网址 + 逐图 key/iv；要 zip 用「打包下载」按钮 |
| 小说详情页有多余的空白图片区 | 小说无封面仍渲染占位图 | §6l：`_header` 对 fiction 不渲染图片区 |
| 打开软件可直接使用、未强制授权 | 权限仅首帧后台静默申请 | §6l：`PermissionGate` 启动强制授权，未授权无法进入 |
| 动漫点收藏“有概率无效” | 收藏未按 AV/NS 区分（两套 id 空间）+ 错误被静默吞掉 | §6m：按 `source` 路由（ns→`v3/nsanimat`），收藏列表合并 AV+NS，error 信封抛错 |
| 首页/分类「更多」下滑不再加载 | `ContentListPage` 无分页 | §6m：滚动到底自动加载下一页（去重 / 到底停止 / 失败重试） |
| 搜索结果下滑不再加载 / 不能下拉刷新 | `SearchTab` 无分页、无刷新 | §6m：复用 `PaginatedContentList`，搜索也分页 + 下拉刷新 |
| 删下载记录连带删了本地文件 | 记录与文件未解耦 | §6k：只删记录，保留成品文件（`remove`/历史删除均不再 `deleteLocal`） |
| 没有搜索历史 | 关键词未持久化 | §6k：`SearchHistoryStore`（无上限 + 逐条删/清空） |
| 图集详情页预览图空白（但能浏览） | `photoRead` 只给页表、无 cover | §6k：用**首张图**当预览封面 + 标题用列表页兜底 |
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
