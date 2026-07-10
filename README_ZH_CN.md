<div align="center">
  <img src="assets/app_icon.png" alt="Kelivo Max Icon" width="100" />
  <h1>Kelivo Max</h1>

  跨平台 Flutter LLM 聊天客户端，自建云同步 + 云端生成。

  [English](README.md) | 简体中文
</div>

<div align="center">
  <img src="docx/screenshot_1.png" alt="聊天界面" width="150" />
  <img src="docx/screenshot_2.png" alt="模型选择" width="150" />
  <img src="docx/screenshot_3.png" alt="工具调用" width="150" />
  <img src="docx/screenshot_4.png" alt="网络搜索" width="150" />
</div>

## Kelivo Max 是什么

Kelivo Max 是基于 [Kelivo](https://github.com/Chevey339/kelivo) 的增强分支，新增核心能力：

- **自建云同步** — 聊天、助手、服务商配置、文件通过你自己的后端服务器双向同步。不依赖任何第三方云服务，数据完全在你的基础设施上。
- **云端生成** — 将生成任务提交到服务器执行，通过 WebSocket 实时接收结果，关掉 App 也能继续跑。不依赖 Firebase/Google 服务——中国大陆可用。
- **无痕清除** — 一键销毁本地所有已同步数据，云端副本不受影响。
- **KMS 密钥加密** — API 密钥在服务端通过 per-user 信封加密 (AES-256-GCM) 加密存储，数据库中不存在明文密钥。

## 下载

[Releases](https://github.com/77ttt-cmd/kelivo_max/releases)

## 功能

### 云同步 & 云执行 (Kelivo Max 新增)
- 自建同步服务端 (`kelivo-sync-server/`) — Dart/shelf 后端 + PostgreSQL
- 双向同步，Last-Write-Wins 冲突解决
- 单条记录 `localOnly` 开关——指定聊天或助手不上云
- 增量文件同步，SHA256 去重
- 云端流式生成，WebSocket 实时中继
- iOS APNs 推送通知（不用 FCM，中国大陆可用）
- Per-user KMS 信封加密保护 API 密钥
- 无痕清除：先预览影响范围，再一键销毁

### 聊天 & AI
- 多服务商：OpenAI、Google Gemini、Anthropic、DeepSeek、Qwen 及任何 OpenAI 兼容 API
- 自定义助手：系统提示词、世界书、记忆
- 多模态输入：图片、PDF、Word、文本文件
- 完整 Markdown 渲染：代码高亮、LaTeX、表格、Mermaid
- MCP (Model Context Protocol) 工具集成，内置 fetch 工具
- 网络搜索：Bing、DuckDuckGo、Exa、Tavily、Brave、SearXNG、Perplexity 等
- 语音：系统 TTS + OpenAI / Gemini / ElevenLabs / MiniMax 语音服务
- 提示词变量、二维码分享、自定义 HTTP 请求头

### 平台
- Android、iOS、macOS、Windows、Linux
- iOS 灵动岛显示后台生成进度
- Android 前台服务保持后台生成
- 桌面端：快捷键、系统托盘、右键菜单
- 自定义字体（系统字体 / Google Fonts）
- 深色模式 + 动态主题色

## 同步服务端

默认服务器：`https://3846-79545ece8ae76c54.monkeycode-ai.live`（App 内已预填）。

### 自建部署

```bash
cd kelivo-sync-server
docker-compose up -d     # 启动 PostgreSQL + 服务端，端口 3846
```

环境变量：
| 变量 | 必须 | 说明 |
|---|---|---|
| `DATABASE_URL` | 是 | PostgreSQL 连接字符串 |
| `JWT_SECRET` | 是 | JWT 签名密钥 |
| `KMS_MASTER_KEY` | 加密时 | 32 字节 hex，信封加密主密钥 |
| `APNS_KEY_ID` | iOS 推送 | Apple 推送通知 Key ID |
| `APNS_TEAM_ID` | iOS 推送 | Apple Developer Team ID |
| `APNS_KEY_P8` | iOS 推送 | APNs 签名密钥内容 |
| `APNS_BUNDLE_ID` | iOS 推送 | App Bundle Identifier |

完整部署指南见 [kelivo-sync-server/README.md](kelivo-sync-server/README.md)。

## 从源码构建

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

要求：Flutter >= 3.44.1, Dart >= 3.12.1

## 架构

```
客户端 (Flutter)                     服务端 (Dart/shelf)
┌──────────────┐                    ┌──────────────────┐
│ SyncProvider  │◄── WebSocket ────►│ RelayService     │
│ SyncApiClient │◄── REST ────────►│ ChangelogService │
│ Handlers (9)  │                   │ EncryptionService│
│ CloudTask     │                   │ StreamDispatcher │
│ IncognitoWipe │                   │ PushService      │
└──────────────┘                    └──────────────────┘
                                           │
                                    ┌──────┴──────┐
                                    │ PostgreSQL  │
                                    └─────────────┘
```

## 致谢

- [Kelivo](https://github.com/Chevey339/kelivo) — 本项目 fork 自 Kelivo
- [RikkaHub](https://github.com/re-ovo/rikkahub) — UI 设计灵感来源

## 许可证

AGPL-3.0 — 见 [LICENSE](LICENSE)。

## 反馈

[GitHub Issues](https://github.com/77ttt-cmd/kelivo_max/issues)
