<div align="center">
  <img src="assets/app_icon.png" alt="Kelivo Max Icon" width="100" />
  <h1>Kelivo Max</h1>

  Cross-platform Flutter LLM chat client with self-hosted cloud sync and cloud-side generation.

  English | [简体中文](README_ZH_CN.md)
</div>

<div align="center">
  <img src="docx/screenshot_1.png" alt="Chat Screen" width="150" />
  <img src="docx/screenshot_2.png" alt="Model Selection" width="150" />
  <img src="docx/screenshot_3.png" alt="Tool Calling" width="150" />
  <img src="docx/screenshot_4.png" alt="Web Search" width="150" />
</div>

## What is Kelivo Max

Kelivo Max is a feature-rich LLM chat client forked from [Kelivo](https://github.com/Chevey339/kelivo), with major additions:

- **Self-hosted cloud sync** — bidirectional sync of chats, assistants, providers, and files through your own backend server. No third-party cloud service. Data stays on your infrastructure.
- **Cloud-side generation** — submit generation tasks to the server and receive results via WebSocket, even after closing the app. No dependency on Firebase or Google services — works in mainland China.
- **Incognito wipe** — one-click local destruction of all synced data without affecting cloud copies.
- **KMS key encryption** — API keys are encrypted at rest on the server using per-user envelope encryption (AES-256-GCM).

## Download

[Releases](https://github.com/77ttt-cmd/kelivo_max/releases)

## Features

### Cloud sync & execution (new in Kelivo Max)
- Self-hosted sync server (`kelivo-sync-server/`) — Dart/shelf backend with PostgreSQL
- Bidirectional sync with Last-Write-Wins conflict resolution
- Per-record `localOnly` toggle — keep specific chats or assistants off the cloud
- Incremental file sync with SHA256 dedup
- Cloud-side streaming generation via WebSocket relay
- APNs push notifications for iOS (no FCM — works in China)
- Per-user KMS envelope encryption for API keys
- Incognito wipe: preview what will be deleted, then one-click destroy

### Chat & AI
- Multi-provider: OpenAI, Google Gemini, Anthropic, DeepSeek, Qwen, and any OpenAI-compatible API
- Custom assistants with system prompts, world books, and memory
- Multimodal input: images, PDFs, Word docs, text files
- Full Markdown rendering with code highlighting, LaTeX, tables, Mermaid
- MCP (Model Context Protocol) tool integration with built-in fetch tool
- Web search: Bing, DuckDuckGo, Exa, Tavily, Brave, SearXNG, Perplexity, and more
- TTS: system TTS + OpenAI / Gemini / ElevenLabs / MiniMax voice providers
- Prompt variables, QR code sharing, custom HTTP headers

### Platform
- Android, iOS, macOS, Windows, Linux
- iOS Live Activities for background generation progress
- Android foreground service for background generation
- Desktop: keyboard shortcuts, system tray, right-click context menus
- Custom fonts (system fonts / Google Fonts)
- Dark mode with dynamic color theming

## Sync server

Default server: `https://3846-79545ece8ae76c54.monkeycode-ai.live` (pre-configured in the app).

### Self-hosting

```bash
cd kelivo-sync-server
docker-compose up -d     # starts PostgreSQL + server on port 3846
```

Environment variables:
| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | Yes | PostgreSQL connection string |
| `JWT_SECRET` | Yes | Secret for signing JWT tokens |
| `KMS_MASTER_KEY` | For encryption | 32-byte hex key for envelope encryption |
| `APNS_KEY_ID` | For iOS push | Apple push notification key ID |
| `APNS_TEAM_ID` | For iOS push | Apple Developer team ID |
| `APNS_KEY_P8` | For iOS push | APNs signing key content |
| `APNS_BUNDLE_ID` | For iOS push | App bundle identifier |

See [kelivo-sync-server/README.md](kelivo-sync-server/README.md) for full setup guide.

## Building from source

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

Requirements: Flutter >= 3.44.1, Dart >= 3.12.1

## Architecture

```
Client (Flutter)                    Server (Dart/shelf)
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

## Acknowledgements

- [Kelivo](https://github.com/Chevey339/kelivo) — the original project this is forked from
- [RikkaHub](https://github.com/re-ovo/rikkahub) — UI design inspiration

## License

AGPL-3.0 — see [LICENSE](LICENSE).

## Issues

[GitHub Issues](https://github.com/77ttt-cmd/kelivo_max/issues)
