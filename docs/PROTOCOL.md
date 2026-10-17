# manmanlu2 (mmlu) v1.5.20 — 第三方客户端协议规格书

> 来源：`com.manmanlu2` v1.5.20 静态逆向（`classes.dex` + `libcipher-lib.so`）。
> 标注约定：**[确认]** = 已从字节码逐指令还原；**[待实测]** = 逻辑确定但未经真实服务器往返验证；**[未知]** = 尚未还原。
> 所有结论附 `code_off`（code_item 偏移）或 `mid`（方法索引，坐标为 dex 0）。

---

## 1. 网络与域名

### 1.1 域名来源（三级）

| 来源 | 说明 | 状态 |
|---|---|---|
| 静态默认 `BaseDomain.kt` | 内置兜底域名，App 启动即可用 | [确认] |
| `host.txt` | 从 `m1.mmlu1.site` / `n1.mmlu1.site` 拉取并 AES 解密，得到全部真域名 | [确认] |
| 启动测速 (`CdnHostResponse` + `DomainTestBean`) | 对候选域名测速，择优写入运行时配置 | [确认] |

**静态默认域名** `Lg/n/l/a/p/a;`（`BaseDomain.kt`，静态字段）：

| 字段 | 值 | 含义 |
|---|---|---|
| b | `api.17mimei.com` | 备用 API |
| c | `https://api.mmlu4.site` | API 数据 |
| d | `https://ac.mmlutech.xyz` | 漫画/图集 CDN |
| e | `""` | comic referer（运行时填充）|
| f | `https://fiction.mmlu4.site` | 小说 |
| g | `https://img.mmlu4.site` | 图片 |
| h | `""` | img referer（运行时填充）|
| i | `https://stream.mmlu4.site` | 流媒体 |
| j | `https://stream.mmlu4.site` | 流媒体（备用）|
| k | `miXFCHEoSXJ.M` | 流媒体 chain [待实测] |
| l | `""` | 备用 |

**host.txt 真域名（已解出）**：

| 类别 | 域名（多线路） |
|---|---|
| api | `api1.mmlu.services` / `api1.ook.cool` |
| comic_avdata | `ac1.mmlutech.xyz` / `ac1.mmlu4.site` |
| fiction | `fiction1.*`（mlu4.services / mmlu4.site 等镜像）|
| img | `img1.*` |
| stream | `stream-encrypt1.mmlutech.xyz` / `stream-encrypt1.mmlu4.site` |

host.txt 源 URL（`Lg/n/i/a;` Constants.kt `<clinit>`）：
`https://m1.mmlu1.site/host.txt`、`https://n1.mmlu1.site/host.txt`

### 1.2 域名的运行时注入

- `SplashPresenter` 拉 `CdnHostResponse`（含 api/comic/fiction/img/stream 五个候选列表 `CdnHostBean{url,hostUrl,chain,cc,referer}`）。
- `Lg/n/b/n/p2;->a(apiBean, comicBean, fictionBean, imgBean, streamBean)`（code_off 49030）：
  - `apiBean.isValid()` → `BaseDomain.a(url)`（写字段 `c`）+ `presenter.C1(API_DATA, url)`
  - `comicBean` → `BaseDomain.b(url)`（写 `d`）+ `BaseDomain.e = comicBean.referer` + `C1(API_COMIC,url)`
  - `fictionBean` → `BaseDomain.c(url)` + `C1(API_FICTION,url)`
  - `imgBean` → `BaseDomain.d(url)` + `BaseDomain.h = imgBean.referer` + `C1(API_IMG,url)`
  - `streamBean` → `BaseDomain.g(url)` + `BaseDomain.h = streamBean.hostUrl` + `BaseDomain.f = streamBean.chain` + `BaseDomain.e = streamBean.cc`(非空时) + `C1(API_STREAM,url)`
- `C1(DomainType, String)`（`Lg/n/b/e/o;->C1`，mid 42577）→ `k.s1(DomainType.getValue(), url)`，即写入键值存储。
- Retrofit baseUrl 取值：Koin 属性表按 `DomainType.value` 读取，缺省回退 `BaseDomain` 对应静态字段。

**DomainType 枚举**（`com/manmanlu2/model/type/DomainType`）：

| 枚举 | value（配置键） | headerValue |
|---|---|---|
| API_DATA | `api_url_data` | api |
| API_COMIC | `api_url_comic` | comic |
| API_FICTION | `api_url_fiction` | fiction |
| API_IMG | `api_url_img` | img |
| API_STREAM | `api_url_stream` | stream |

> 第三方客户端可跳过 host.txt/测速，直接使用上表默认或 host.txt 域名。

---

## 2. 传输层

- HTTP 客户端：OkHttp（`Ln/w`），超时 connect/read/write = **30s**（`Lg/n/d/p3;`）。
- Retrofit（`Lp/b0`）+ Gson 转换器（lenient）。
- 拦截器链顺序（`Lg/n/d/n3;`）：**HeaderInterceptor → RequestInterceptor → TimeoutInterceptor**。

| 拦截器 | 类 | code_off | 作用 |
|---|---|---|---|
| HeaderInterceptor | `Lg/n/l/a/r/a;` | 5252808 | 加 `platform: Android`、`version: 1.5.20` |
| RequestInterceptor | `Lg/n/l/a/r/b;` | 5253124 | 加 `payload`、`ebody` 头（**不改 body**）|
| TimeoutInterceptor | `Lg/n/l/a/r/c;` | 5253496 | 读并移除 `CONNECT_TIMEOUT`/`READ_TIMEOUT`/`WRITE_TIMEOUT` 头覆盖超时 |

### 2.1 固定请求头

```
platform: Android
version: 1.5.20
```

HeaderInterceptor 细节：`version` 值取常量 `1.5.20`，若含 `-` 则截断到 `-` 之前（本次无后缀）。
`Authorization: Bearer <token>` 为**接口方法级参数**（`@Header("Authorization")`），110/111 个接口带此参数（仅 `v2/register` 无）。

**值格式 [实测确认]**：必须为 `Bearer ` + token，其中 token 是**服务端签发的 JWT 风格串**，形如 `base64(payload).md5hex.randomhex`
（例：`eyJ1c2VyX2lkIjoxMTk3MzgsImxhc3Rsb2dpbiI6MTc5MjIwODc5Mn0.<32hex>.<…hex>`，payload=`{"user_id":..,"lastlogin":..}`）。
- 缺失 / 空 / 非 `Bearer ` scheme → HTTP 499 `{"error":"缺少 Token 參數"}`。
- `Bearer ` 后为非服务端签发串（无论形状）→ HTTP 498 `{"error":"Token 格式錯誤"}`。
- `foo bar`、`Basic abc` 等非 Bearer scheme → 499。

> 注：APK 中 `Authorization` 值由 `BaseRepo.getMToken()` 透传（未拼 Bearer），而登录成功回调 `Lg/n/b/j/n0/w0;->invoke` 把 `"Bearer " + TokenResponse.token` 写回存储 —— 即**存储值本身已含 `Bearer ` 前缀**，所以真正发出的头确实是 `Bearer <token>`；dex 里 `Bearer ` 是加密串（`Lh/a/a/a;->a` 解密）。

`x-package`、`referer` 亦为方法级 `@Header` 参数。

---

## 3. 请求签名（`payload` / `ebody` 头）

`RequestInterceptor`（`Lg/n/l/a/r/b;->intercept`，code_off 5253124）当自身字段 `a`（RequestHashBean）为空时，构造：

```kotlin
RequestHashBean(payload = null, path = request.url.encodedPath.substring(1), mask = 1, marker = null)
```

`RequestHashBean` 4 参构造（code_off 5076584）：
- `mask & 1` → `payload = ThreadLocalRandom.current().nextLong(0x3b9aca00, 0x2540be3ff).toString()`
  - `0x3b9aca00 = 1_000_000_000`，`0x2540be3ff = 9_999_999_999` → **10 位随机数字串 nonce**
- `mask & 2` → `path = ""`（本次 mask=1，path 保持传入值）

`RequestHashBean` 2 参构造（code_off 5076160）计算 `ebody`：

```
# 1) 明文（Gson 序列化 SecureBody{path,payload}）
secureBody = { "path": path, "payload": G2(nonce) }
json       = JSONObject(Gson().toJson(secureBody)).toString()   # 紧凑 JSON

# 2) Key = MD5( Base64.decode(secureKey,0) ) 的小写十六进制（BigInteger 语义，不补零！）
keyBytes = Base64.DEFAULT.decode(CipherClient.secureKey())          # 32 字节
md5      = MessageDigest("MD5").digest(keyBytes)                    # 16 字节
key      = BigInteger(1, md5).toString(16)                          # ⚠ 小写、无前导零，长度可能为 31
secret   = SecretKeySpec(key.getBytes(), "AES")

# 3) IV = G2(nonce).getBytes(UTF-8)
ivSpec   = IvParameterSpec(G2(nonce).getBytes(UTF-8))

# 4) 加密
cipher   = Cipher.getInstance("AES/CBC/PKCS5Padding")
cipher.init(ENCRYPT_MODE, secret, ivSpec)
ebody    = Base64.encodeToString(cipher.doFinal(json.getBytes(UTF-8)), Base64.NO_WRAP)
```

然后请求加头：

```
payload: <nonce>
ebody:   <ebody>
```

**辅助函数**
- `G2(s) = MD5hex_zp(s).substring(8, 24)`（`g/j/a/d/d/o/f;->G2`，mid 35324）——16 字符，用于 IV。
- `MD5hex_zp(s)`（`g/n/o/c;->f`，mid 50445）= 标准 MD5，逐字节 `Integer.toHexString(b & 0xff)` 且**左补零到 2 位**，**小写**。
- ⚠ 注意两处 MD5 语义不同：`G2` 用补零小写；`ebody` 的 key 用 `BigInteger(1,digest).toString(16)`（**不补零**）。

> 这是**请求签名/防篡改**机制（服务端可校验 path + G2(payload)），**并非对 body 加密**。真正的业务 body 原样明文 JSON 发送。

---

## 4. 响应解密

`Lg/n/l/a/i;->invoke`（mid 50041）作为响应变换器：

```
if response.header("X-App-Name") == "app":
    iv      = G2(response.header("X-Response-Length")).getBytes(UTF-8)   # 16 字节
    key     = MD5hex_zp(CipherClient.apiKey()).getBytes(UTF-8)           # 32 字节（c.f，补零小写）
    cipher  = Cipher.getInstance("AES/CBC/PKCS5Padding")
    cipher.init(DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
    plain   = new String(cipher.doFinal(Base64.decode(body, Base64.NO_WRAP)))   # 默认字符集
    return plain
else:
    return body   # 明文
```

即：当响应头 `X-App-Name: app` 时，响应体为 **Base64(NO_WRAP) 的 AES-256-CBC(PKCS5) 密文**，key = `MD5hex_zp(apiKey)`，iv = `G2(X-Response-Length)`。

`EncodeUtility`（`Lg/n/o/c;`）：
| 方法 | code_off | 语义 |
|---|---|---|
| a(String)[B | 5266556 | `Base64.decode(s, DEFAULT)` |
| b(IvSpec,SecretKeySpec,String)String | 5266904 | `Base64.decode(s, NO_WRAP)` → `AES/CBC/PKCS5.decrypt` → `new String(bytes)`（默认字符集）|
| e(B[],B[],String)String | 5266984 | AES 加密（SecretKeySpec "AES"，`AES/CBC/PKCS5Padding`，`Base64.encodeToString(...,NO_WRAP)`）；**前置拼接 IV** 的变体，非 ebody 路径 |
| f(String)String | 5267172 | MD5 → 补零小写 hex |

### 4.1 host.txt 解密

`Lg/n/l/a/j;->invoke`（mid 50044，host 响应映射器）：

```
key    = Base64.decode(CipherClient.hostKey(), DEFAULT)     # 32 字节
iv     = Base64.decode(CipherClient.hostIv(),  DEFAULT)     # 16 字节
plain  = EncodeUtility.b(IvParameterSpec(iv), SecretKeySpec(key,"AES"), bodyBase64)   # AES-256-CBC/PKCS5
result = plain.substring(32, plain.length - 32)             # 去掉首尾各 32 字符
```

---

## 5. 密钥常量

`CipherClient`（`net/idik/lib/cipher/so/CipherClient`，native `libcipher-lib.so`）解密所得：

| 名称 | 值 | 用途 |
|---|---|---|
| apiKey | `6e561ccd4aade2fed458d4da61e76770` | 响应解密 key 源 |
| secureKey | `OlFXpWEoON2n+EuUuvDOod5lauDh98GLYmCsvBgMwts=` | ebody key 源（base64）|
| appKey | `uh4S4k3AYe1LqViQuMgeWntH8L0=` | [待实测] |
| apiEncryptHeaderKey | `qv5ntw2zk3V4dUMZ8fLX/Rd9n40dz+Gos4U2DXOv7to=` | [待实测] |
| hostKey | `Kp0YhE24edXfJySdI4U/naedvDbWvXQKAlUp5zpVCh4=` | host.txt 解密 key（base64）|
| hostIv | `TNzGV5P8ikpnNZOnK5Z3XA==` | host.txt 解密 iv（base64）|
| comicDecryptKey | `C2A830A5E687678418F88F652984E925` | 漫画资源 [待实测] |
| comicDecryptIV | `958DB2E92B361F373BFB35CCCC296FBB` | 漫画资源 |
| imgDecryptKey | `B2F3842866F9583D1ECE61C4E055C255` | 图片资源 |
| imgDecryptIV | `E01EDE6331D37AFCC7BE05597D654D22` | 图片资源 |
| nsAnimeImageDecryptKey | `204149A15B092E24E89CEB31040148DB` | 动漫图 |
| nsAnimeImageDecryptIv | `AC14AECE2E0681EE730A4D773F3B2EE6` | 动漫图 |
| nsComicDecryptKey | `D94E86BC48615C397146E9A1CA0870E244F2C7920D7535D2F20039E9D54AD810` | NS 漫画 |
| nsComicDecryptIv | `CA87D9018CC39C86FA25E7876AC079CB` | NS 漫画 |

---

## 6. 鉴权与登录 【已实测打通】

### 6.0 引导流程（三步，实测通过）

App 首次进入时**无 token**，但除 `v2/register` 外所有接口都强制 `Authorization`。因此必须先做**设备引导注册**取得「游客 token」：

```
① 设备注册（无 Authorization）
   POST v2/register
   body = {"universal_id":<uuid>, "platform":2, "model":"<BRAND>_<MODEL>",
           "key":<见下>, "install_channel":"com.android.vending", "install":"", "source":""}
   key = SHA-256( "hcg" + universal_id + "hcg" ).hexdigest()      # 64 位小写 hex，务必一致
   -> {"success":{"token":<游客token>, "user_id":<游客uid>, "universal_id":<uuid>}}

①b 激活会话（Authorization: Bearer <游客token>，★注册后必做）
   GET v2/combine/startup?platform=2
   -> {"success":{"userInfo":{...},...}}
   不做这步：游客 token 访问内容类接口会回 200 `{"error":{"msg":"unidentify"}}`（并非 495）。

② 账号登录（Authorization: Bearer <游客token>）
   POST v2/user/login
   body = {"country_codes":"86","phone":"<手机>","password":"<明文密码>","platform":2}
   -> {"success":{"token":<账号token>, "user_id":<账号uid>}}

③ 之后所有请求  Authorization: Bearer <账号token>
```

实测结果：以 `86-15152012300 / 1314ZLY` 登录成功，返回 `user_id=119738729`；
`v2/user/info` 返回 `level=2`（→ isVip=true）。

> `key` 的构造来自 `SplashPresenter.J1()`（`Lg/n/b/n/z2;`，code_off 4968332）：
> `deviceId` = 注册时生成的 uuid；`key = SHA-256("hcg"+deviceId+"hcg")` 的 hex。
> `RegisterTokenBody` 构造顺序（构造器 code_off 5084536）=
> `(universalId, platform, model, key, install_channel, install, source)`；
> JSON 经 Gson `@SerializedName` 映射为 snake_case（`universal_id` 等）。

### 6.1 本地实现要点

- 存储：SharedPreferences 名 `17memie`；token key `pref_app_token`（默认 `""`）。
  - 登录/注册成功后回调把 **`"Bearer " + token`** 写入（`w0`/`z3->invoke`）。
- `MemberRepo.login(LoginBody)`（mid 14522）：`getApiService().D(getMToken(), loginBody)`；
  `MemberRepo.register(RegisterTokenBody)`（mid 14532）：`getApiService().P(body)`（无 Authorization）。
- `TokenResponse`（classDefIdx 915）：字段 `UUID`(=`universal_id`)、`token`、`userId`(=`user_id`)，
  经 `toTokenResponse`（code_off 5135516）解析。
- `RegisterTokenBody`（classDefIdx 867）：`install, install_channel, key, model, platform, source, universalId`。

### 6.2 服务端错误码【实测】

| 场景 | HTTP | body |
|---|---|---|
| 无/空/非 Bearer 的 Authorization | 499 | `{"error":"缺少 Token 參數"}` |
| `Bearer ` + 非法 token | 498 | `{"error":"Token 格式錯誤"}` |
| 游客 token **未 startup** 访问内容类接口 | 200 | `{"error":{"msg":"unidentify"}}`（注册后未激活） |
| 注册字段缺失 | 401 | `{"error":{"universal_id":["The universal id field is required."]}}` |
| 注册 key 错误 | 401 | `{"error":{"msg":"key error"}}` |
| 登录成功 | 200 | `{"success":{"token":…,"user_id":…}}` |

> **游客 token 激活后即可浏览内容**（实测 2026-10-17）：`register → startup` 后，
> 游客 token 请求 `v3/comic/ns/new`、`v3/nsanimat/new`、`v3/fiction/new`、`v2/comic/banner`
> 均正常返回数据；播放 m3u8/分片与解密也不依赖账号。**账号仅影响收藏/历史/VIP**。
> 未 startup 直接访问内容类接口才会得到 `unidentify`。故第三方客户端可「免登录」浏览。

---

## 7. 接口总表

- 共 **111** 个端点，分布在 8 个 Retrofit 接口文件；聚合接口 `ApiService.kt`（`Lg/n/l/a/s/b;`，110 个抽象方法、无注解）与委托实现 `ApiServiceImpl.kt`（`Lg/n/l/a/s/c;`，7 个委托字段）。
- 另存在 `StreamService.kt`（`Lg/n/l/a/s/k;`，1 方法 4 参）——独立流媒体接口。

服务接口与归档：`AnimateApi.kt(a)=20`、`AppApi.kt(d)=8`、`CollectApi.kt(e)=9`、`ComicApi.kt(f)=37`、`FictionApi.kt(g)=18`、`MemberApi.kt(h)=14`、`SearchApi.kt(i)=4`、`StreamApi.kt(j)=1`。

> 每条均为：`@Header("Authorization") token` 作首参（除 `v2/register`）；通用头 `platform`/`version`/`payload`/`ebody` 由拦截器自动附加，下表不再重复。

### 01 应用配置 / 启动 / 行为（6）
```
GET    v2/common/appinfo                              # 应用信息（含 system.is_free 全站免费开关）
GET    v2/vcheck                  x-package           # 版本校验
GET    v2/combine/startup         platform(I)         # 启动聚合
GET    v2/common/news/2                               # 公告
GET    v3/common/advert                               # 广告
GET    v2/behavior                type(String)        # 行为上报
```

### 02 用户 / 账户（11）
```
POST   v2/user/login              Body(LoginBody)
POST   v2/user/checkPassword      Body(CheckPwdBody)
POST   v2/user/forgetPassword     Body(ResetPwdBody)
GET    v2/user/checkCode          action(String),code(String)
GET    v2/user/code               action(String),country_codes(String),phone(String)
GET    v2/user/info
GET    v2/user/share
GET    v2/user/shareinfo
POST   v2/user/bindPhone          Body(SetPwdBody)
POST   v2/user/changePassword     Body(ChangePwdBody)
POST   v2/user/changePhone        Body(ChangeMobileBody)
```

### 03 会员 / 支付 / 注册（4）
```
GET    v2/payment/payments
POST   v2/payment/buy             plan_id(I),payment_id(I)
GET    v2/payment/history         page(Integer),limit(Integer)
POST   v2/register                Body(RegisterTokenBody)   # 无 Authorization
```

### 04 漫画 / 图集（37）
```
GET    v2/combine/comic/index                 type(Integer),platform(I)
GET    v2/comic/banner                        type(Integer),platform(I)
POST   v2/comic/classic                       wrap_classic(String)
GET    v2/comic/classic                       category_type(Z),x-package
GET    v2/comic/continued                     type(Integer)
GET    v2/comic/korea                         end(I),counts(I),pages(I)
GET    v2/comic/new                           type(Integer),counts(I),pages(I)
GET    v2/comic/rand /rand2 /rand3 /rand4      (type/tag,counts,pages)
GET    v2/comic/ranking                       type(Integer),counts(I),pages(I),range(I)
GET    v2/comic/read                          id(I),counts(I),pages(I)
GET    v2/comic/recommend                     type(Integer),counts(I),pages(I)
POST   v2/comic/report                        Body(ReportBody)
DELETE v2/comic/favorite                      ids(String)
PUT    v2/comic/favorite/{comic_id}
GET    v3/combine/data/comic/internal/{comic_id}
DELETE v3/comic/data/favorite                 ids(String)
PUT    v3/comic/data/favorite/{comic_id}
PUT    v3/comic/data/history/{chapter_id}     last_page(I)
GET    v3/comic/data/new                      type(Integer),counts(I),pages(I)
GET    v3/comic/data/read                     chapter_id(I),counts(I),pages(I),user_type(Z),sdb(String)
GET    v3/comic/ns/category                   type(Integer),counts(I),pages(I)
GET    v3/comic/ns/classic/detail             id(I),type(Integer),sort(I),counts(I),pages(I)
DELETE v3/comic/ns/favorite                   ids(String)
PUT    v3/comic/ns/favorite/{comic_id}
PUT    v3/comic/ns/history/{chapter_id}       last_page(I)
GET    v3/comic/ns/internal/{id}
GET    v3/comic/ns/korea                      end(I),counts(I),pages(I)
GET    v3/comic/ns/new                        type(Integer),counts(I),pages(I)
GET    v3/comic/ns/ranking                    type(Integer),counts(I),pages(I),range(I)
GET    v3/comic/ns/read                       comic_id(I),counts(I),pages(I),user_type(Z),sdb(String)
GET    v3/comic/ns/recommend                  type(Integer),counts(I),pages(I)
GET    v3/photo/read                          id(I),counts(I),pages(I)
GET    v3/photo/similar                       id(I)
GET    v3/photo/tag
```

### 05 动画（20）
```
POST   v2/animat/classic                      wrap_classic(String)
GET    v2/animat/classic
GET    v2/animat/continued                    type(Integer)
GET    v2/animat/rand /rand2 /rand3            (type/tag,counts,pages)
GET    v2/animat/series                       tag(String),counts(I),pages(I)
DELETE v2/animat/favorite                     ids(String)
PUT    v2/animat/favorite/{animate_id}
PUT    v2/animat/history/{animate_id}
POST   v2/animat/report                       Body(ReportBody)
GET    v2/combine/animat/index                type(Integer),platform(I),user_type(Z),x-package
GET    v2/combine/animat/internal/{animate_id}
GET    v3/nsanimat/classic/detail             id(I),type(I),sort(I),counts(I),pages(I)
DELETE v3/nsanimat/favorite                   ids(String)
PUT    v3/nsanimat/favorite/{animate_id}
GET    v3/nsanimat/internal/{animate_id}
GET    v3/nsanimat/new                        type(I),counts(I),pages(I)
GET    v3/nsanimat/ranking                    type(I),counts(I),pages(I),range(I)
GET    v3/nsanimat/recommend                  type(I),counts(I),pages(I)
```

### 06 小说（17）
```
GET    v2/combine/fiction/index               type(Integer),platform(I)
GET    v2/fiction/categoryText
POST   v2/fiction/classic                     wrap_classic(String)
GET    v2/fiction/classic
GET    v2/fiction/classic/detail              id(I),type(I),sort(I),counts(I),pages(I)
GET    v2/fiction/continued
DELETE v2/fiction/favorite                    ids(String)
PUT    v2/fiction/favorite/{fiction_id}
PUT    v2/fiction/history/{fiction_id}        percent(F)
GET    v2/fiction/new                         type(I),counts(I),pages(I)
GET    v2/fiction/rand /rand2 /rand3           (type/tag,counts,pages)
GET    v2/fiction/ranking                     type(I),counts(I),pages(I),range(I)
GET    v2/fiction/recommend                   type(I),counts(I),pages(I)
POST   v2/fiction/report                      Body(ReportBody)
GET    v2/fiction/summary/{fiction_id}        user_type(Z),x-package
GET    (dynamic @Url)                         # 小说下载代理
```

### 07 收藏 / 历史（9）— `{type}` = comic / animat / fiction
```
GET    v2/{type}/favorite                     counts(Integer),pages(Integer)
DELETE v2/{type}/favoriteAll
GET    v2/{type}/history                      range(I),counts(Integer),pages(Integer)
DELETE v2/{type}/history                      ids(String)
GET    v3/{type}/data/favorite                counts(Integer),pages(Integer)
DELETE v3/{type}/data/favoriteAll
GET    v3/{type}/favorite                     counts(Integer),pages(Integer)
GET    v3/{type}/ns/favorite                  counts(Integer),pages(Integer)
DELETE v3/{type}/ns/favoriteAll
```

### 08 搜索（4）— `{type}` = comic / animat / fiction
```
GET    v2/search/tag
GET    v2/search/{type}                       keywords(String),sort(I),pages(I),counts(I)
GET    v3/search/data/{type}                  keywords(String),sort(I),pages(I),counts(I)
GET    v3/search/ns/{type}                    keywords(String),sort(I),pages(I),counts(I)
```

### 10 流媒体 / 下载代理（3）
```
GET    (AppApi @Url)      Url(String), Header:referer(String), @Headers
GET    (FictionApi @Url)  Url(String)
GET    (StreamApi @Url)   @Streaming, Header:Authorization, Url(String), host(String), chain(String)
```

合计 6+11+4+37+20+17+9+4+3 = **111**。

---

## 8. 数据模型要点

- 响应**有统一信封 [实测确认]**：成功 `{"success": <data>}`，失败 `{"error": <detail>}`。
  例如 `v2/user/info` 解密后为 `{"success":{"id":..,"level":2,"phone":..}}`；
  `v2/payment/payments` 为 `{"success":[{...}]}`；`v2/common/appinfo` 为 `{"success":{...}}`。
  客户端应解包 `success` 后再取字段（早期「无信封」判断已推翻）。
- `AppInfoResponse`：`_id, ad(FullScreenAdGson), android(AppGson), categoryList(List,=`category_list`), chatGroup, floatBtnGroup, newsUrl, prompt, share, system(SystemGson)`
- 全站免费开关：`system.is_free` / `system.is_free_message`
- `UserInfoResponse`：`{id, phone, country_codes, level:Integer, level_expiry_at:Long, lock:Integer}`
- `MemberBean`：`{_id, countryCode, mobile, level, levelExpiryAt, lockStamp}`
- `isVip` = `MemberModel.k0.b()`（mid 46225）= `getLevel() > 1`
- `PaymentBean{id,title,sub_title,currency}`、`PaymentsResponse.payments`、`BuyPaymentResponse{data,type}`
- 请求体 Bean：`LoginBody`、`CheckPwdBody`、`ResetPwdBody`、`SetPwdBody`、`ChangePwdBody`、`ChangeMobileBody`、`RegisterTokenBody`、`ReportBody`（字段 [未知]，待逐个 dump）

---

## 9. 会员 / VIP 模型

- 全站免费开关 `system.is_free`。
- 客户端 VIP 闸门**仅两处实质功能**：**① 高速线路 ② 动漫高清**（用户已证实；锁章属"分享解锁"，非会员）。
  - 播放器 `VideoPresenter`（`Lg/n/b/d/g/x2;`）：`T0`（mid 42450，清晰度切换）与 `z1`（mid 42460，线路切换）均判断 `if (!isVip && !isFree) return/拦截`。
  - 底层数据解析（`parseAnimate` mid 14050）**无 VIP 过滤**；域名/CDN 获取（启动页 `getCdnDomainHost`，mid 49012）**不携带 VIP 参数**。
- 结论：**第三方客户端可绕过 VIP 闸门**。实测：游客 token（level 0）与 VIP token 请求同一动漫详情，服务端返回**完全相同的 `media`（含 `720`）** → 高清判断纯客户端；线路同理，服务端不区分。[已实测]

---

## 9B. 流媒体（动画）播放协议 【已还原 · 沙箱可复现解密】

### 9B.1 播放线路来源

`host.txt` 的 `stream` 数组 = 播放线路，即客户端 `VideoModel.lineDomainList`
（元素 `DomainBean{name, url, hostUrl, chain, cc, referer}`）。实测：

| 线路 | url | chain | tsurl | name |
|---|---|---|---|---|
| 1 | `https://api1.mmlu.services` | `miOBGgHNWhpt2` | `https://stream-encrypt1.mmlutech.xyz` | 国内线路1 |
| 2 | `https://api1.ook.cool` | `miOBGgHNWhpt2` | `https://stream-encrypt1.mmlu4.site` | 国内线路2 |

> chain 实测值 = `miOBGgHNWhpt2`（来自 host.txt）。`BaseDomain.k = miXFCHEoSXJ.M` 是另一处静态默认串，**不是**链值。
> `tsurl` 主机即拉流时 `?host=` 的取值，决定服务端为哪台 CDN 主机签名。

### 9B.2 取媒体路径（⭐v3 与 v2 两条路，分片签名不同）

同一 `animate_id` 两个详情接口都返回 `summary[].media = {"intro":..., "720":..., "240":...}`，
但**媒体路径版本不同 → 分片 URL 的签名策略不同**（实测，2026-10-17）：

| 详情接口 | media 路径 | m3u8 里的分片 |
|---|---|---|
| **`GET v3/nsanimat/internal/{id}`** | `/v3/nsanimat/media/720/<avkey>.m3u8` | **`https://na.mmlu1.site/apen/<avkey>/ts/<avkey>-N.ts`（无签名，可直接下）** |
| `GET v2/combine/animat/internal/{id}` | `/v1/animat/media/720/<avkey>.m3u8` | `na.mmlu1.site/...?Expires=&Signature=&Key-Pair-Id=`（CloudFront 签名） |

> **第三方客户端首选 v3**：分片无签名、免鉴权、可直下（`key.php` 与 `*.ts` 均公开可取）。
> v3 与 v2 的 `media` 值（avkey）可能不同；`directory[]` 同理带 `media`。

> ⭐ **详情必须按 `source` 路由（关键！）**：AV 与 NS 是**两套 id 空间**，
> `v2/combine/animat/internal/{id}` 与 `v3/nsanimat/internal/{id}` 对同一个 id 返回**不同作品**。
> 实测（2026-10-17）搜索「鬼父」：结果项 `source='av'`、`id=14767`；
> - `v2/combine/animat/internal/14767` → **正确**「鬼父 Rebuild…」，media `/v1/animat/media/...`；
> - `v3/nsanimat/internal/14767` → **别的作品**「【MMD】飞霄…」（200，静默串台）；
> - 大量 AV id（1..25 等）`v3/nsanimat/internal` → **HTTP 410 `资源无法存取`**。
>
> 故：`source='av'` 用 **v2/combine/animat**（媒体 `/v1/animat/media`，**署名 CloudFront 分片**），
> `source='ns'`/缺省用 **v3/nsanimat**（媒体 `/v3/nsanimat/media`，无签名分片）；410/404 时互相回退。
> 早前「一律走 v3」是**错误**的，会导致「搜索展示与点开内容不符」与「点开 410 network error」。
>
> AV 链路实测可播：`/v1/animat/media/720/GHOSTFATHER-0008.m3u8` 解密后为标准 HLS，
> 分片为 `na.mmlu1.site/apen/<avkey>/ts/<avkey>-N.ts?...Signature=...&Key-Pair-Id=...`（**有签名**，
> 但**随 m3u8 实时下发**、`key.php` 16B、AES-128-CBC 解密后 len%188==0）。故每次播放/下载
> 都要**重新拉一次 m3u8** 以取新签名。

### 9B.3 拉取并解密 m3u8

```
GET  {line.url}{media_path}?host={host}&chain={line.chain}
Header: Authorization: Bearer <token>
```

- `host` 取 `tsurl` 主机（如 `na.mmlu1.site` / `stream-encrypt1.mmlutech.xyz`）；
  实测 v3 路径下 `host` 填任一线路主机都得到同一份 `na.mmlu1.site` 分片；**`host` 缺省会失败**
  （连接被重置），务必带上。
- 响应 `content-type: text/plain`，带 `x-app-name: app` + `x-response-length`
  → 复用 **§4 标准响应解密**（key=`md5hex_zp(apiKey)`，iv=`G2(x-response-length)`）；
  注意 key/iv 都是 **32/16 字符按 ASCII 直接当字节**（不 hex 解码）。
- ⚠ `media_path` 以 `/` 开头，与 API 域拼接时**勿产生双斜杠**——
  `https://api1.mmlu.services//v3/...` 会返回 **404**（实测踩坑）。
- 明文为标准 HLS VOD 清单（实测 `v3/nsanimat/media/720/JDXA55712.m3u8`，304 段）：
```
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:6
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-KEY:METHOD=AES-128,URI="https://na.mmlu1.site/apen/<avkey>/key.php",IV=0x<hash>
#EXTINF:6.006000,
https://na.mmlu1.site/apen/<avkey>/ts/<avkey>-0.ts
...（数十~数百个分片）
```
- URI 可能省略 `https://` 前缀（v2/AV 路径常见，形如
  `URI="stream-encrypt1.mmlutech.xyz/apen/.../key.php?Expires=...&Key-Pair-Id=..."`）；
  **解析时必须补全 scheme**，否则请求报 `DioException: No host specified in URI`。
  分片行也可能为协议相对 `//host/...` → 补 `https:`。无签名 URL（v3 路径）可直接下载。

### 9B.3b 分片解密（HLS AES-128，⭐实测通过）

- `GET <key.php>`（免鉴权）→ **16 字节 ASCII 密钥**（原样当 AES-128 key）。
- 每段 `*.ts`（免鉴权）→ **AES-128-CBC** 解密：`key=上述16字节`，`IV=m3u8 里 EXT-X-KEY 的 IV`
  （**全片同 IV**），**默认 PKCS7 去填充**（明文为 188 整数倍 MPEG-TS）。
- 拼接全部段 = 完整 MPEG-TS（H.264 + AAC），可直接播放。
- 实测：`v3/nsanimat/media/720/JDXA55712.m3u8` 304 段；8 段拼接 46138 包，
  0x47 同步率 **1.0000**。
- 参考实现：`tools/mmlu_api.py` 的 `animat_media(version=3)` / `get_m3u8` /
  `parse_m3u8` / `aes_cbc_decrypt128` / `download_hls`；CLI：`m3u8 <id> [q]`、`dl <id> [q] [out.ts]`。

### 9B.4 App 的本地代理（端口 1140）

App 启动本地 HTTP 服务 `http://localhost:1140`，把播放地址指到本机：

- `/temp_hd.m3u8`、`/temp_sd.m3u8` ← 拉取+解密上面的 m3u8 后重写再吐给播放器。
- 重写规则（实测常量）：正则 `(https?://.*/.*.ts.*)` 替换为 `?ts_url=$1`，并把 `&` 替成 `%26`；
  即分片改走 `/temp_ts?ts_url=<原始签名URL>`。
- 本地代理再带 `Authorization` 去 CDN 取回 ts 明文回放（HLS AES-128 解密由播放器/代理完成）。
- 相关符号：`StreamRepo.getM3u8Request(domain, videoUrl, fileName, hostUrl, chain, localTsTempPath)`
  （mid 14582）→ `StreamService.a(@Url url, @Query("host"), @Query("chain"), @Header("Authorization"))`
  （接口 `Lg/n/l/a/s/k;`，唯一方法 `a`，flags 1025 `@Streaming`）。

> **沙箱实测（2026-10-17 更新）**：走 **v3/nsanimat 路径**时，分片是**无签名** `na.mmlu1.site`
> URL，**可直下**（`key.php` 200/16B，`*.ts` 200 ~840KB）。偶发 `Connection reset` 是网络抖动，
> **重试即通**（工具已内置重试）。
> 而 v2/combine 路径（`/v1/animat/media`）分片是 CloudFront **签名 URL**，在沙箱易 403/重置。
> 因此第三方客户端**用 v3 路径即可直接下载播放**，无需本地代理。
> App 自带的本地代理（§9B.4）是其播放器架构选择，非协议必需。

---

## 9C. 图片 / 漫画 / 图集 / 小说资源解密 【已实测】

所有图片资源都是「下载密文 → AES-CBC 解密 → 直接得到 JPEG」，无二次包装。
**密钥分两种来源**：①全局固定密钥（ns 动漫图 / ns 漫画）②接口逐图下发 key/iv。

### 9C.0 资源域名（§1.1 的 img / comic / fiction）

| 资源 | host | 说明 |
|---|---|---|
| 动漫缩略图/封面 | `img1.mmlutech.xyz` / `img1.mmlu4.site` | `path = thumbpath` / `coverpath` |
| 漫画封面 / 阅读页 / 图集封面 / 图集图片 | `ac1.mmlutech.xyz` / `ac1.mmlu4.site` | 漫画与图集**共用** comic 域 |
| 小说正文 | `fiction1.mmlutech.xyz` / `fiction1.mmlu4.site` | `path = filepath` |
| 动漫视频 | 见 §9B | —— |

> host 双线路逐一尝试（一台可能 DNS/连接失败）；`path` 可能**无前导 `/`**（av 漫画/图集），拼接时必须补 `/`。

### 9C.1 动漫图（固定 AES-128-CBC）

- 来源：`v3/nsanimat/new`/`internal` 等列表项的 `thumbpath`、`coverpath`（`/imgs/thumb/xx/<hex>.jpg`）。
- 密文 → **AES-128-CBC** 解密：`key=hex("204149A15B092E24E89CEB31040148DB")`、
  `iv=hex("AC14AECE2E0681EE730A4D773F3B2EE6")`（即密钥常量 `nsAnimeImageDecryptKey/Iv`），默认 PKCS7。
- 实测：thumb 62048B → 62039B `ffd8ffe0`(JPEG)；cover 171632B → `ffd8ffe0`。**[实测]**

### 9C.2 漫画 — 详情接口（拿章节）

| 来源 | 详情接口 | 返回 |
|---|---|---|
| `source=ns` | `GET v3/comic/ns/internal/{id}` | `{summary[], directory[], samelike[]}` |
| `source=av` | `GET v3/combine/data/comic/internal/{comic_id}` | `{summary[], directory[], samelike[], samelike2[]}` |

`directory[]` 每项含 **`chapter_id`**（≠ 列表 item 的 `id`！）与 `cover{cover_path,key,iv}`。
⚠ 实测踩坑：`directory[].id` 是漫画 id，**阅读要用 `chapter_id`**。

### 9C.2b 相似作品（samelike）— 实测 2026-10-17

| 种类 | 来源 | 返回字段 |
|---|---|---|
| 动漫 | `v2/combine/animat/internal/{id}` | `{summary[], directory[], samelike[30], samelike2[30]}` |
| 动漫(ns) | `v3/nsanimat/internal/{id}` | 同上结构 |
| 漫画(ns) | `v3/comic/ns/internal/{id}` | `{summary[], directory[], samelike[]}` |
| 漫画(av) | `v3/combine/data/comic/internal/{comic_id}` | `{summary[], directory[], samelike[], samelike2[]}` |
| 图集 | `GET v3/photo/similar?id={id}` | `{data:[...]}`（**独立接口**，详情 `v3/photo/read` 只返页表） |

- `samelike[]` 每项结构 = 列表 item（动漫含 `id/avkey/name/series/season/ep/source/media/coverpath`）。
- ⚠ **实测 `samelike` 与 `samelike2` 完全相同**（30/30 同序），动漫侧取其一即可。
- ⚠ 图集 similar 项封面字段为 `cover`（**Map**：`{cover_path,key,iv}`，逐图方案），非 `coverpath`。
- ⚠ `GET v2/animat/series?tag=` **不按系列名过滤**（返回默认流）；跨条目查同系列用
  **搜索接口** `v2/search/animat?keywords={系列名}`（实测「必杀痴汉人」→ 前编 449 + 后编 447）。
- 例：动漫 id=449「必杀痴汉人 前编」`directory[2]` 已含前编+后编（同 `series` 分集聚合靠 `directory`）。

### 9C.3 漫画 — 阅读接口（拿页表）

| 来源 | 阅读接口 | 返回 |
|---|---|---|
| `ns` | `GET v3/comic/ns/read?comic_id={id}` | `{data:[<页路径字符串>...]}`（全局固定密钥） |
| `av` | `GET v3/comic/data/read?chapter_id={chapter_id}` | `{data:[{image_path,key,iv}...]}`（**逐页 key/iv**） |

- ⚠ `v3/comic/ns/read` 参数名是 **`comic_id`**；传 `id` → **410 `资源无法存取`**。
- ⚠ `v3/comic/data/read` 参数名是 **`chapter_id`**；传 `comic_id` → 400 缺 `chapter_id`；传错值 → 500。
- 可选参数：`counts,pages,user_type(Z),sdb(String)`。

### 9C.4 漫画 — 封面 / 页解密

- **ns 漫画**（`source=ns`）：**AES-256-CBC**，全局固定
  `key=hex("D94E86BC48615C397146E9A1CA0870E244F2C7920D7535D2F20039E9D54AD810")`、
  `iv=hex("CA87D9018CC39C86FA25E7876AC079CB")`（= 密钥常量 `nsComicDecryptKey/Iv`）。
  其 `cover.key/iv` 字段值正是这两个常量（hex）。封面与阅读页同密钥。
  实测：封面 17792B → `ffd8ffdb`；页 6368B → `ffd8ffdb`。**[实测]**
  - ⚠ **收藏等接口的 ns 封面可能改回 Base64 逐图 key/iv**（非固定 hex）。客户端
    `_coverOf` 需检测：key 为 Base64（长度 4 的倍数、含 `+/=`、非 32/64 位纯 hex）
  → 按 `perImage`(b64) 解，否则用固定方案；否则收藏第一个(ns)漫画会解密失败、不显示封面。
- **av 漫画**（`source=av`）：**AES-256-CBC**，**逐图下发** `key`/`iv`（**Base64**，解出 32B/16B）。
  实测：封面 28992B → `ffd8ffe1`；页 1098224B/1806976B → `ffd8ffe1`。**[实测]**

### 9C.5 图集

- 列表：`v3/photo/new`/`ranking`/`recommend` → item `{id,name,tag,cover{cover_path,key,iv},pages,...}`。
- 阅读：`GET v3/photo/read?id={id}` → `{data:[{image_path,key,iv}...]}`（**逐图 key/iv**）。
- 解密：**AES-256-CBC**，`key=Base64.decode(key)`、`iv=Base64.decode(iv)`，默认 PKCS7。
  实测：封面 30528B → `ffd8ffe1`；图片 470000B → `ffd8ffe1`。**[实测]**

### 9C.6 小说

- 列表：`v3/fiction/new`/`ranking`/`recommend`、`v2/fiction/summary/{id}` → item 含 `title/desc/filepath/filepath_tw`。
- 正文：`GET {fiction host}{filepath}`（如 `https://fiction1.mmlutech.xyz/zhcn/AU9/<hash>.txt`）。
- **明文 UTF-8**（无加密；`filepath`=简体，`filepath_tw`=繁体）。实测 131620B，直接是中文正文。**[实测]**
- ⚠ **正文必须走 fiction 域**（`fiction1.mmlutech.xyz` / `fiction1.mmlu4.site`）。
  实测同一 `filepath` 用 `ac1.mmlutech.xyz`（comic 域）→ **403**，用 `ac1` 拼接还会 `Connection reset`。
  客户端 `ResourceService.urlFor` 对 `ContentKind.fiction` 取 `apiFiction`。
- 小说条目**无 `cover` 字段**（列表/详情都没有），UI 不应渲染封面图。

### 9C.7 资源解密速查

```
动漫图   : AES-128-CBC  key=nsAnimeImageDecryptKey(hex)  iv=nsAnimeImageDecryptIv(hex)
漫画(ns) : AES-256-CBC  key=nsComicDecryptKey(hex)       iv=nsComicDecryptIv(hex)
漫画(av) : AES-256-CBC  key=b64(item.key)                iv=b64(item.iv)
图集     : AES-256-CBC  key=b64(item.key)                iv=b64(item.iv)
小说正文 : 明文
```

---

## 9D. 写操作（收藏 / 历史 / 举报 / 账户 / 支付）【已实测】

所有写请求复用与 GET **相同的头**（`platform`/`version`/`payload`/`ebody`/`Authorization`），
业务体为**明文 JSON**。`ebody` 只是 path+nonce 的防篡改签名，**不加密 body、也不阻塞写操作**（实测全通）。

> ⚠ 密集写请求与读一样会触发**瞬时限流**（502），间隔 ~2s 稳妥。

### 9D.1 收藏（增 / 删 / 列 全通，实测）

| 操作 | 接口 |
|---|---|
| 列表(动画/小说) | `GET v2/{type}/favorite?counts=&pages=` → `{lastPage,total,data[]}` |
| 列表(漫画 ns) | `GET v3/comic/ns/favorite?counts=&pages=` |
| 列表(漫画 av) | `GET v3/comic/data/favorite?counts=&pages=` |
| 添加 | `PUT v2/animat/favorite/{animate_id}` · `PUT v2/fiction/favorite/{fiction_id}` · `PUT v3/comic/ns/favorite/{comic_id}` · `PUT v3/comic/data/favorite/{comic_id}` |
| 删除 | `DELETE v2/{type}/favorite?ids=<id[,id...]>`（逗号分隔） |
| 清空 | `DELETE v2/{type}/favoriteAll` · `v3/{type}/data/favoriteAll` · `v3/{type}/ns/favoriteAll` |

- `{type}` = `animat` / `fiction`（图集 photo **无**收藏接口）。
- ⚠ **漫画收藏列表必须用 v3**：`v2/comic/favorite` 已失效（稳定 500/502，两个 api 域均然）；
  正确为 `v3/comic/ns/favorite`（ns）与 `v3/comic/data/favorite`（av），实测 200。
- 添加返回 `{data:{id, user_id, <x>_id, created_at, updated_at}}`；删除返回 `{data:<删除条数>}`。
- 实测周期（均已复原）：动画 48→47→48（`PUT .../favorite/733`）；漫画 ns 0→1→0；漫画 av PUT/DELETE 通；小说 PUT/DELETE 通。

### 9D.2 历史（**写入已实测**；列表接口当前异常）

| 操作 | 接口 | body/query |
|---|---|---|
| 写(动画) | `PUT v2/animat/history/{animate_id}` | — |
| 写(小说) | `PUT v2/fiction/history/{fiction_id}` | `percent`(F) |
| 写(漫画 ns) | `PUT v3/comic/ns/history/{chapter_id}` | `last_page`(I) |
| 写(漫画 av) | `PUT v3/comic/data/history/{chapter_id}` | `last_page`(I) |
| 列表(动画/小说) | `GET v2/{type}/history?range=&counts=&pages=` | `range` **必填且 ∈{1,2}**（0 → 400） |
| 列表(漫画 ns) | `GET v3/comic/ns/history?range=&counts=&pages=` | 同上 |
| 删除 | `DELETE v2/{type}/history?ids=` | — |

- 写入返回 `{data:"success"}` 或 `{data:{id,user_id,<x>_id,updated_at}}`（实测 200）。
- ⚠ **动漫/小说列表** `v2/{type}/history` 实测多为 `total:0`（**非报错**，就是空）。
- ⚠ **漫画列表必须用 v3** `v3/comic/ns/history`（实测 200，返回数据）；
  旧的 `v2/comic/history` 已失效（500）。图集 photo **无**历史列表接口（404）。
- `range` 服务端校验 `≥1`（`range=0` → `400 {"range":["The range must be at least 1."]}`）。

### 9D.3 举报（ReportBody 字段已探明）

`POST v2/{comic|animat|fiction}/report`，Body：`{id:Integer, device:String, question:String}`。

### 9D.4 账户（Body 字段已探明）

| 接口 | Body 字段 |
|---|---|
| `POST v2/user/checkPassword` | `{password}` → `{"msg":"密码正确"}` |
| `POST v2/user/changePassword` | `{old_password, password}` |
| `POST v2/user/changePhone` | `{country_codes, phone, code}` |
| `POST v2/user/bindPhone` | `{country_codes, phone, code, password}` |
| `POST v2/user/forgetPassword` | `{country_codes, phone, code, password}` |
| `GET  v2/user/code?action=&country_codes=&phone=` | **发送短信验证码**（⚠ 有副作用）→ `{title,msg}` |
| `GET  v2/user/checkCode?action=&code=` | 校验验证码 |
| `GET  v2/user/share` · `v2/user/shareinfo` | → `{text, url}`（分享文案/落地页 `https://d1.csa.baby`） |

### 9D.5 支付（读 + 下单参数）

- `GET v2/payment/payments` → `[{id, title, sub_title, currency}]`（实测 1 项：人民币/支付宝）。
- `POST v2/payment/buy?plan_id=&payment_id=`（参数为 **query**；空参返回 `{}`）。
- `GET v2/payment/history?page=&limit=` → `{orders:[], total, page}`。

---

## 10. 待确认项（不做估算）

1. ~~token 头是否带 `Bearer ` 前缀~~ —— **[已实测] 是**：`Authorization: Bearer <token>`（见 §6.2）。
2. ~~`MD5hex_zp` / `BigInteger.toString(16)` 与服务端一致性~~ —— **[已实测] 一致**（ebody/响应解密实测全通）。
3. ~~`v2/combine/startup` 与 `v2/vcheck` 哪个返回域名字段~~ —— **[已实测] 都不返回域名**：
   `v2/combine/startup` 返回 `{userInfo, announce, shareInfo, advert}`；
   `v2/vcheck` 是**另一种信封** `{"code":200,"message":"success","result":{"check":false}}`（上游代理）。
   域名实际来自 host.txt（§1.1）与 CDN 端点 `getCdnDomainHost`（§1.2）。
4. 各 `@Body` Bean 字段列表：`LoginBody`/`RegisterTokenBody` [已确认]；其余（CheckPwd/ResetPwd/SetPwd/ChangePwd/ChangeMobile/Report）[未知]
5. AppApi `@Url` 上的 `@Headers` 具体值 —— [未知]
6. ~~`BaseDomain.k = miXFCHEoSXJ.M` 与 stream chain `miOBGgHNWhpt2` 冲突~~ —— **[已核实] 无关**：
   stream chain 真值 = `miOBGgHNWhpt2`（来自 host.txt `stream[].chain`，见 §9B.1）；
   `BaseDomain.k` 是别的静态默认串。
7. ~~资源密钥（comicDecryptKey 等）用于**图片/章节**解密的具体算法~~ —— **[已实测]**：
   动漫图 AES-128-CBC(固定)、漫画 ns/av 与图集 AES-256-CBC、小说明文，见 **§9C**。
   （`comicDecryptKey/imgDecryptKey` 未用于以上路径，疑为旧版/其他模块，[未知]。）
8. ~~错误响应结构~~ —— **[已实测]**：未加密明文 `{"error":{...}}`（401/498/499），见 §6.2；成功响应 `X-App-Name: app` 时为 AES 密文。
9. ~~图片/漫画/图集/小说资源能否解密~~ —— **[已实测] 全部可解**（§9C）：详情 `v3/comic/ns/internal/{id}`、
   av 详情 `v3/combine/data/comic/internal/{comic_id}`、阅读 `v3/comic/ns/read?comic_id=`、
   `v3/comic/data/read?chapter_id=`、`v3/photo/read?id=`、小说 `v2/fiction/summary/{id}` + `filepath` 明文。
10. ~~系统分享面板是否调 API~~ —— [已实测] `Z0()` 仅拉起系统分享，无 API（见 §9 会员模型旁注）。
11. 服务端对密集请求会**瞬时限流**（连续探测返回 502 Bad Gateway，`v2/user/info` 亦 502）；放慢/重试即恢复。**[实测]**
12. ~~写操作能否实现~~ —— **[已实测] 可以**（§9D）：收藏增/删/列全通、历史写入通、账户/举报 Body 字段全部探明。
    写请求复用同一套头，`ebody` 不阻塞。唯一异常是**历史列表**接口返回空/500（疑服务端问题，非协议问题）。
13. ~~是否有会员专享章节~~ —— 用户反馈实际使用中**无会员章节**；服务端亦不区分（§9）。

---

## 附录 A：参考实现（Dart，供 Flutter 使用）

```dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';          // sha/md5
import 'package:encrypt/encrypt.dart' as enc;  // AES-CBC

String md5HexZp(String s) {
  final d = md5.convert(utf8.encode(s)).bytes;              // 16 bytes
  return d.map((b) => b.toRadixString(16).padLeft(2, '0')).join(); // 补零小写
}

/// BigInteger(1, md5(bytes)).toString(16) —— 小写、不补零
String md5HexBigInt(Uint8List bytes) {
  final d = md5.convert(bytes).bytes;
  final hex = d.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return hex.replaceFirst(RegExp(r'^0+'), '');              // 去前导零
}

String g2(String s) => md5HexZp(s).substring(8, 24);        // 16 chars

// ebody: key = MD5(base64decode(secureKey)) -> BigInteger.toRadixString(16)
String buildEbody(String secureKey, String path, String nonce) {
  final keyStr = md5HexBigInt(base64.decode(secureKey));
  final key = enc.Key(utf8.encode(keyStr));
  final iv  = enc.IV(utf8.encode(g2(nonce)));
  final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  final plain = jsonEncode({'path': path, 'payload': g2(nonce)});
  return encrypter.encrypt(plain, iv: iv).base64;           // NO_WRAP
}

// 响应解密: X-App-Name==app
String decryptResponse(String apiKey, String xResponseLength, String bodyB64) {
  final key = enc.Key(utf8.encode(md5HexZp(apiKey)));
  final iv  = enc.IV(utf8.encode(g2(xResponseLength)));
  final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  return encrypter.decrypt(enc.Encrypted.fromBase64(bodyB64), iv: iv);
}

String newNonce() {
  final r = Random.secure();
  final n = 1000000000 + r.nextInt(9000000000 - 1);          // [1e9, 9e9) 近似
  return n.toString();
}
```

> 注意：`encrypt` 包的 `Encrypted.base64` 默认标准 Base64；Android `Base64.NO_WRAP` 等价于不带换行的标准 Base64。

## 附录 B：一条命令实测（Python，沙箱可跑）

```bash
python3 - <<'PY'
import base64,hashlib,json,random,requests
APIKEY="6e561ccd4aade2fed458d4da61e76770"
SECUREKEY="OlFXpWEoON2n+EuUuvDOod5lauDh98GLYmCsvBgMwts="
def md5zp(s): return hashlib.md5(s.encode()).hexdigest()
def g2(s): return md5zp(s)[8:24]
def ebody(path,nonce):
    key=hashlib.md5(base64.b64decode(SECUREKEY)).digest().hex().lstrip('0')
    from Crypto.Cipher import AES
    from Crypto.Util.Padding import pad
    c=AES.new(key.encode(),AES.MODE_CBC,g2(nonce).encode())
    return base64.b64encode(c.encrypt(pad(json.dumps({"path":path,"payload":g2(nonce)}).encode(),16))).decode()
base="https://api1.mmlu.services"
p="v2/common/appinfo"; n=str(random.randint(10**9,10**10-1))
h={"platform":"Android","version":"1.5.20","payload":n,"ebody":ebody(p,n)}
r=requests.get(base+"/"+p,headers=h,timeout=30)
print(r.status_code, r.headers.get("X-App-Name"), r.text[:300])
PY
```
（实测需有效 token；缺 token 预期返回 499。）
