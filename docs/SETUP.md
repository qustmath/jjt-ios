# iOS 上架一次性配置指引（个人开发者账号）

按顺序做，全程约 1~2 小时（不含苹果审核等待）。每一步做完打个勾。

---

## 第 1 步：加入 Apple Developer Program（$99/年）

1. iPhone 上下载 **Developer** App（App Store 搜 "Apple Developer"）
   —— 用 App 注册可以支付宝/微信付款 ¥688/年；网页注册只能外币信用卡
2. 打开 App → 账户 → **Enroll Now / 现在注册**
3. 身份选 **Individual / 个人**，填真实姓名（会显示在 App Store「开发者」一栏，不可改）
4. 付款，等激活邮件（个人号通常几分钟~几小时）

✅ 激活标志：https://developer.apple.com/account 能进入后台，不再提示 enroll

---

## 第 2 步：创建 App ID

1. 后台 → **Certificates, Identifiers & Profiles** → **Identifiers** → ➕
2. 选 **App IDs** → **App**
3. 填：
   - Description：`JJT`
   - Bundle ID 选 **Explicit**：`ink.groovy.jjt`（与安卓包名一致）
   - Capabilities 勾选：**Push Notifications**（后续 IM 推送要用，先勾上）
4. Register

---

## 第 3 步：创建 App Store Connect 应用记录

1. 打开 https://appstoreconnect.apple.com → **我的 App** → ➕ **新建 App**
2. 填：
   - 平台：iOS
   - 名称：荆棘兔
   - 主要语言：简体中文
   - 套装 ID：选刚建的 `ink.groovy.jjt`
   - SKU：`jjt-ios`（内部标识，随意）
3. 创建后**记下 App 的 Apple ID**（App 信息页，一串数字）——选填，后续自动回复评论等用得到

---

## 第 4 步：创建 App Store Connect API Key（CI 上传凭证）

1. App Store Connect → **用户和访问** → **集成** → **App Store Connect API** → **团队密钥** → ➕
   （若提示无权限，需先在「协议、税务和银行业务」里同意付费协议；个人号即账户持有人本身）
2. 名称 `ci-upload`，访问级别选 **App 管理**（或 管理）
3. 生成后：
   - **下载 AuthKey_XXXXXXXXXX.p8**（只能下一次！）
   - 记下 **Key ID**（10 位）和 **Issuer ID**（UUID 格式）
4. 本地转 base64（Git Bash 执行）：
   ```bash
   base64 -w0 ~/Downloads/AuthKey_XXXXXXXXXX.p8 > /tmp/p8.b64
   ```

---

## 第 5 步：创建 match 证书私有仓库

fastlane match 把签名证书加密存在一个**独立的私有 git 仓库**里：

1. GitHub 新建私有仓库：`jjt-ios-certs`（Private，不用初始化任何文件）
2. 生成仓库访问 token：GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token，勾 **repo** 权限
3. 生成 basic auth（Git Bash）：
   ```bash
   echo -n "你的GitHub用户名:刚生成的token" | base64 -w0
   ```
4. 想一个 match 加密口令（任意强密码，**自己记牢**，它是加密证书的钥匙）

---

## 第 6 步：填 GitHub Secrets

iOS 代码仓库 → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**，逐个添加：

| Name | 值 | 来源 |
|---|---|---|
| `APP_IDENTIFIER` | `ink.groovy.jjt` | 第 2 步 |
| `TEAM_ID` | 10 位字符 | developer.apple.com/account → Membership details |
| `APP_STORE_CONNECT_KEY_ID` | 10 位 | 第 4 步 |
| `APP_STORE_CONNECT_ISSUER_ID` | UUID | 第 4 步 |
| `APP_STORE_CONNECT_API_KEY_B64` | 一长串 base64 | 第 4 步 `/tmp/p8.b64` 内容 |
| `MATCH_GIT_URL` | `https://github.com/你的用户名/jjt-ios-certs.git` | 第 5 步 |
| `MATCH_GIT_BASIC_AUTHORIZATION` | base64 串 | 第 5 步 |
| `MATCH_PASSWORD` | 你定的口令 | 第 5 步 |

---

## 第 7 步：首次发布到 TestFlight

1. 仓库 → **Actions** → **iOS** → **Run workflow** → release 填 `true` → 运行
2. 首次运行 match 会自动：创建发布证书 → 创建 App Store 描述文件 → 加密推送到 `jjt-ios-certs` 仓库（全自动，不用干预）
3. 构建成功后约 10~30 分钟，App Store Connect → **TestFlight** 出现构建版本
4. TestFlight → **内部测试** → 添加自己（Apple ID 邮箱）→ 手机装 **TestFlight** App 即可安装

## 第 8 步：日常迭代（对应安卓"写代码→打包→装机"）

```
改代码 → push master（自动编译验证）
      → 要装机时：Actions 手动 Run workflow（release=true）
      → 10 分钟后 TestFlight 收到新版本 → 手机更新
```

---

## 常见问题

- **"缺少合规性"提示**：TestFlight 里构建版本选「不提供加密豁免」或我们在 Info.plist 加 `ITSAppUsesNonExemptEncryption=false`（后续加）
- **兔币充值**：苹果 3.1.1 条款要求虚拟币必须走 IAP 内购，上架前需改造，否则拒审
- **构建失败看日志**：Actions → 失败的那次运行 → 点开红色步骤
