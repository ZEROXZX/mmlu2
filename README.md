# mmlu_client

manmanlu2 (`com.manmanlu2` v1.5.20) 第三方 Flutter 客户端骨架。
协议依据：`docs/PROTOCOL.md`（全部从 dex + native 静态还原，字节级）。

> 环境：已在本机（Ubuntu 24.04 / glibc 2.39 / aarch64，位于 Termux 的 proot-distro 内）安装
> **Flutter 3.47.7 stable + Dart 3.13.5（官方 arm64 host 制品）**，位于 `/opt/flutter`，已写入
> `PATH`（`/root/.bashrc` 与 `/etc/profile.d/flutter.sh`）。
> 已验证：`flutter analyze` 0 问题，`flutter test` 9/9 全绿（含 OpenSSL 金标向量）。
>
> **协议已联网实测打通**：设备注册(游客 token) → 账号登录 → 鉴权接口全通。
> 实测账号 `86-15152012300`，`v2/user/info` 返回 `level=2`（VIP）。见 `docs/PROTOCOL.md` §6。
>
> **流媒体协议已还原并实测解密**：`v2/combine/animat/internal/{id}` 取媒体路径 →
> `GET {line.url}{path}?host=&chain=`（Bearer）→ 标准响应解密 → 得到标准 HLS m3u8
> （CloudFront 签名 URL + HLS AES-128）。见 `docs/PROTOCOL.md` §9B。

## 目录结构

```
lib/
  main.dart                         入口 + 冒烟测试页
  app/app_container.dart            轻量 DI（等价 Koin ApplicationModule）
  core/
    constants/mmlu_keys.dart        14 个 native 密钥 + 固定头常量
    crypto/mmlu_crypto.dart         MD5/G2/AES-CBC/ebody/响应解密/host解密
    domain/domain_store.dart        DomainType + 运行时域名存储
    domain/endpoints.dart           111 条接口路径常量
    auth/token_store.dart           token 持久化 (pref_app_token)
    network/
      header_interceptor.dart       platform/version 头
      sign_interceptor.dart         payload/ebody 头（请求签名）
      decrypt_interceptor.dart      响应 AES 解密
      api_client.dart               Dio 组装 + 鉴权 + 错误处理 + host.txt
      api_exception.dart
  data/
    api/api_service.dart            接口方法（代表性实现 + 通用底层）
    models/*.dart                   TokenResponse / AppInfoResponse / ...
    repo/member_repo.dart           登录 / 设备注册 / 用户 / VIP
    repo/app_repo.dart              appinfo / 域名解析
test/crypto_test.dart               金标向量自测（OpenSSL 生成）
docs/PROTOCOL.md                    协议规格书
tools/mmlu_api.py                   已实测的 Python 参考实现（register/login/smoke）
```

## 关键实现点

- **拦截器链顺序**与 App 一致：`Header → Auth → Sign → Decrypt → Error`。
- **鉴权**：`AuthInterceptor` 注入 `Authorization: Bearer <token>`（服务端强制该前缀，
  否则 499/498）。登录前须先 `v2/register` 设备注册取游客 token（`MemberRepo.ensureToken`）。
- **请求签名**（`sign_interceptor.dart`）只加 `payload`/`ebody` 头，**不加密 body**。
  `ebody` 的 AES key 用 `BigInteger(1, MD5(Base64(secureKey))).toString(16)`（不补零），
  与 `md5HexZp`（补零）区分，已在 `MmluCrypto` 分别实现。
- **响应解密**：仅当响应头 `X-App-Name: app`；key=`md5HexZp(apiKey)`，iv=`G2(X-Response-Length)`。
  解密后是统一信封 `{"success":<data>}`，`DecryptInterceptor` 自动解包。
- **域名**：默认用 `BaseDomain` 静态值；`AppRepo.getCdnDomainHost` + `applyCdnHosts` 可择优覆盖。

## 自测

```bash
flutter test                          # 校验 crypto 与 OpenSSL 金标一致

# 联网实测（Python 参考实现，需 curl/openssl）
python3 tools/mmlu_api.py smoke                             # 设备注册 + 两个 GET 冒烟
python3 tools/mmlu_api.py login 86 <手机号> <密码>          # 完整登录，写 .state.json
python3 tools/mmlu_api.py get v2/user/info                  # 用已存 token 请求
python3 tools/mmlu_api.py lines                             # 打印播放线路（host.txt stream）
python3 tools/mmlu_api.py m3u8 734 720                      # 取+解密动漫 734 的 720p HLS 清单
```

> `m3u8` 解密已在沙箱复现（拿到完整 HLS 播放清单）。但清单里的 key/ts 是
> CloudFront **签名 URL**，直连返回 403 `AccessDenied`（疑似来源 IP 约束/反滥用），
> 真机可播放；第三方客户端宜自带本地代理（同 §9B.4）。

## 环境搭建（本机已装，复现实录）

本机是 Termux 内的 **proot-distro Ubuntu 24.04 (aarch64)**，官方 archive 不提供 Linux ARM64 的
SDK bundle（`releases_linux_arm64.json` 为 404），因此用「克隆 stable 分支 + 让 flutter 工具按
host 架构自动拉取 arm64 制品」的方式安装：

```bash
apt-get update && apt-get install -y git xz-utils unzip zip curl file ca-certificates
git config --global --add safe.directory /opt/flutter
git clone --depth 1 -b stable https://github.com/flutter/flutter.git /opt/flutter
export PATH=/opt/flutter/bin:$PATH
export PUB_CACHE=/root/.pub-cache
flutter --version     # 自动下载 dart-sdk-linux-arm64 + engine；首次约 3~5 分钟
```

`bin/internal/update_dart_sdk.sh` 会按 `uname -m`（aarch64→arm64）选取 `dart-sdk-linux-arm64.zip`。

> `flutter doctor` 中 Android toolchain / Chrome / Linux desktop 工具链缺失属预期；
> `flutter test`（VM 运行 Dart 单测）不需要它们。若要 `build apk` 需另装 Android SDK+JDK。

## 已验证 / 待补（见 docs/PROTOCOL.md 第 10 节）

已实测：`Bearer ` 前缀、register/login 全流程、响应信封 `{"success":...}`、错误 schema、
`LoginBody`/`RegisterTokenBody` 字段、`v2/user/info`(level=2 VIP)、
`startup`/`vcheck` 内容、游客 vs VIP 高清返回一致、**m3u8 拉取+解密全流程**。

待补：
1. `@Url` 下载代理的 `@Headers` 值
2. 资源密钥（comic/img/ns*）图片/章节解密算法（视频 m3u8 走标准响应解密，已确认）
3. 其余 @Body bean（CheckPwd/ResetPwd/SetPwd/ChangePwd/ChangeMobile/Report）字段
