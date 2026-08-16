# 荆棘兔子 iOS（jjt-ios）

荆棘兔子 iOS 原生客户端，SwiftUI + 纯代码工程（XcodeGen 生成 .xcodeproj，无需 Mac 本地开发，GitHub Actions 云构建）。

## 工程结构

```
JJT/
├── App/            # 入口 + 全局状态（登录态路由）
│   ├── JJTApp.swift
│   └── AppState.swift
├── Core/
│   ├── Config.swift            # API 域名等全局配置
│   ├── Network/
│   │   ├── APIClient.swift     # 网络层：Bearer Token、401 自动刷新重放
│   │   └── AuthAPI.swift       # 认证接口（对齐安卓 AuthApi）
│   └── Storage/
│       ├── KeychainHelper.swift
│       └── TokenManager.swift  # 登录态 Keychain 持久化
├── Design/
│   └── NoirTheme.swift         # Noir 黑金主题
├── Features/
│   ├── Auth/                   # 登录（密码/验证码）
│   └── Main/                   # 四主 Tab：首页/广场/密语/我的
└── Assets.xcassets/
```

## 本地构建（需要 macOS）

```bash
brew install xcodegen
xcodegen                       # 生成 JJT.xcodeproj
open JJT.xcodeproj             # 或命令行：
xcodebuild -scheme JJT -destination 'platform=iOS Simulator,name=iPhone 15' build
```

## CI（GitHub Actions）

- **push 到 master**：自动跑「模拟器编译验证」，不需要任何账号/Secrets
- **手动触发 release=true**：签名打包上传 TestFlight（需先完成 [docs/SETUP.md](docs/SETUP.md) 的一次性配置）

## 环境

- iOS 16.0+
- Swift 5 / Xcode 15.4+
- 后端 API 域名在 `JJT/Core/Config.swift`（默认生产环境）
