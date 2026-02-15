# プロジェクト概要

このディレクトリには、ブラウザの開発者ツールと統合する「Claude」というツールの開発環境のセットアップを自動化するために設計された一連のPowerShellスクリプトが含まれています。これらのスクリプトは、ローカルのWindowsマシンとリモートのLinuxホストの両方を含む複雑なワークフローを容易にします。

設定は `config/config.json` で中央集約管理されており、ブラウザ設定、ポート管理、Claude Code の環境変数・設定（`claudeCode` セクション）、Agent Teams 機能などを一元的に制御します。

スクリプトの主要な機能は以下の通りです。
1.  **プロジェクト選択:** `X:\` ドライブにあるディレクトリのリストから、ユーザーが対話的にプロジェクトを選択するように促します。
2.  **ポート管理:** ブラウザのリモートデバッグプロトコルに使用する、定義済み範囲（デフォルト: 9222-9229）内の利用可能なポートを自動的に見つけます。
3.  **ブラウザの自動化:**
    *   専用の一時ユーザープロファイルとリモートデバッグポートを有効にして、Microsoft EdgeまたはGoogle Chromeの新しいインスタンスを起動します。
    *   `defaultBrowser` 設定によりデフォルトブラウザを指定可能です。
    *   DevTools環境を最適化するためにブラウザの `Preferences` ファイルを事前に設定します（例：キャッシュの無効化、ログの保持）。
4.  **リモートスクリプトの生成:** 選択されたプロジェクトディレクトリ内に `run-claude.sh` という名前のシェルスクリプトを動的に作成します。このスクリプトには、リモートマシンで「Claude」ツールを起動するために必要なコマンドと環境変数が含まれています。初期プロンプト（`INIT_PROMPT`）はヒアドキュメント構文（`INIT_PROMPT=$(cat << 'INITPROMPTEOF' ... INITPROMPTEOF)`）を使用して定義されており、バッククォートや二重引用符を安全に含むことができます。
5.  **リモート実行:**
    *   事前に設定されたLinuxホストにSSHを使用して接続します。
    *   スクリプトや設定ファイルはbase64エンコードでSSH経由で安全に転送されます（改行コードやエスケープの問題を回避）。
    *   生成された `run-claude.sh` スクリプトに実行権限（`chmod +x`）を設定します。
    *   `autoCleanup` が有効な場合、Linuxホスト上のターゲットポートを使用している可能性のあるプロセスを自動クリーンアップします。
    *   リモートポートフォワーディング（`remote port forwarding`）を使用したSSH接続を確立し、リモートLinux環境がローカルWindowsマシンのブラウザのDevToolsと通信できるようにします。
    *   `run-claude.sh` スクリプトを実行して、メインアプリケーションを起動します。
6.  **Claude Code 設定の中央管理:** `config.json` の `claudeCode` セクションで環境変数（`env`）とアプリケーション設定（`settings`）を一元管理し、グローバル `settings.json` に `jq` を用いて包括的にマージ適用します（statusLine だけでなく、全設定項目が対象）。
7.  **Agent Teams 機能:** 環境変数 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` を設定することで、複数の Claude Code インスタンスをチームとして協調動作させるオーケストレーション機能が利用可能です。

# ファイル構造

```
Claude-EdgeChromeDevTools/
├── config/
│   └── config.json                      # 中央設定ファイル（ポート、ブラウザ、claudeCode設定等）
├── scripts/
│   ├── main/
│   │   ├── Claude-EdgeDevTools.ps1      # Edge版メインスクリプト
│   │   └── Claude-ChromeDevTools-Final.ps1  # Chrome版メインスクリプト
│   ├── setup/
│   │   ├── setup-windows-terminal.ps1   # Windows Terminal自動設定
│   │   └── setup-windows-terminal.bat   # Windows Terminal設定ガイド
│   ├── test/
│   │   ├── test-edge.ps1               # Edge接続テスト
│   │   └── test-chrome.ps1             # Chrome接続テスト
│   └── statusline.sh                    # Claude Code Statuslineスクリプト
├── docs/
│   ├── SystemAdministrator/             # システム管理者向けドキュメント
│   └── non-SystemAdministrator/         # 一般ユーザー向けドキュメント
├── start.bat                            # 対話型ランチャー
├── CLAUDE.md                            # Claude Code用プロジェクト指示ファイル
└── GEMINI.md                            # プロジェクトドキュメント（日本語）
```

## 主要ファイルの説明

*   `config/config.json`: 中央集約設定ファイル。ポート、ブラウザパス、`claudeCode`セクション（環境変数・設定の一元管理）などを含みます。
*   `scripts/main/Claude-EdgeDevTools.ps1`: Microsoft Edgeで開発環境をセットアップするためのメインスクリプト。
*   `scripts/main/Claude-ChromeDevTools-Final.ps1`: Google Chromeで開発環境をセットアップするためのメインスクリプト。
*   `scripts/test/test-edge.ps1`: リモートデバッグが有効なEdgeインスタンスへの接続をテストするためのユーティリティスクリプト。
*   `scripts/test/test-chrome.ps1`: リモートデバッグが有効なChromeインスタンスへの接続をテストするためのユーティリティスクリプト。
*   `scripts/statusline.sh`: Claude Code Statusline表示スクリプト。
*   `start.bat`: 対話型メニューからスクリプトを選択して実行するランチャー。

# プロジェクトの実行方法

## 対話型ランチャー（推奨）
```cmd
start.bat
```
対話型メニューからスクリプトを選択して実行します。Windows Terminal推奨。

## 直接スクリプト実行
PowerShellターミナルから実行します。

**Edgeのセットアップを実行する場合:**
```powershell
.\scripts\main\Claude-EdgeDevTools.ps1
```

**Chromeのセットアップを実行する場合:**
```powershell
.\scripts\main\Claude-ChromeDevTools-Final.ps1
```

**前提条件:**
*   `X:\` ドライブがマッピングされており、プロジェクトディレクトリが含まれている必要があります。
*   SSHホスト（`config.json` の `linuxHost` で設定）に対してSSHキーベース認証が構成されている必要があります。
*   Microsoft Edgeおよび/またはGoogle Chromeがデフォルトの場所にインストールされている必要があります。
*   `claude` コマンドラインツールがリモートLinuxホストで利用可能である必要があります。
*   `jq` がLinuxホストにインストールされている必要があります（未インストールの場合は自動インストールを試行します）。

# 開発規約

*   **エラー処理:** スクリプトは `$ErrorActionPreference = "Stop"` を使用して、コマンドが失敗した場合にすぐに終了するようにしています。
*   **ユーザーインタラクション:** スクリプトは対話型であり、明確なステータスメッセージを提供し、ユーザーに情報（例：プロジェクト選択、ポート番号）の入力を求めます。
*   **リモート操作:** すべてのリモート操作はSSHを介して実行され、ファイルシステム操作（`chmod`）やプロセス管理（`fuser`）が含まれます。
*   **base64 SSH転送:** スクリプトや設定ファイルをLinuxホストに転送する際、base64エンコード方式を使用しています。これにより、改行コード（CRLF/LF）やシェルエスケープの問題を回避し、バイナリセーフな転送を実現します。例: `[Convert]::ToBase64String(...)` でエンコード後、SSH経由で `base64 -d` でデコードして書き込みます。
*   **ポートフォワーディング:** スクリプトは、リモートLinux環境とローカルブラウザインスタンス間の通信を橋渡しするために、SSHリモートポートフォワーディング（`-R`）に依存しています。
*   **コード構造:** スクリプトはコメントを使用して論理的なセクションに整理されており、ワークフローを理解しやすくなっています。設定変数は `config/config.json` で中央管理されています。
*   **設定のjqマージ:** グローバル `settings.json`（`~/.claude/settings.json`）の更新には `jq` を使用した包括的なマージ処理を行います。statusLine 設定だけでなく、`claudeCode.env` および `claudeCode.settings` で定義された全項目（言語、出力スタイル、Agent Teams 環境変数など）が既存設定を保持しつつマージ適用されます。

# config.json 設定リファレンス

`config/config.json` はプロジェクトの中央集約設定ファイルです。

```json
{
  "ports": [9222, 9223, 9224, 9225, 9226, 9227, 9228, 9229],
  "zDrive": "X:\\",
  "linuxHost": "kensan1969",
  "linuxBase": "/mnt/LinuxHDD",
  "edgeExe": "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
  "chromeExe": "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
  "defaultBrowser": "edge",
  "autoCleanup": true,
  "statusline": {
    "enabled": true,
    "showDirectory": true,
    "showGitBranch": true,
    "showModel": true,
    "showClaudeVersion": true,
    "showOutputStyle": true,
    "showContext": true
  },
  "claudeCode": {
    "env": {
      "ENABLE_TOOL_SEARCH": "true",
      "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
      "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "50",
      "CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION": "true"
    },
    "settings": {
      "language": "日本語",
      "outputStyle": "Explanatory",
      "alwaysThinkingEnabled": true,
      ...
    }
  }
}
```

### 設定項目の説明

| キー | 説明 |
|------|------|
| `ports` | 使用可能なDevToolsポート配列 |
| `zDrive` | Windowsプロジェクトルート |
| `linuxHost` | SSHホスト名 |
| `linuxBase` | Linuxプロジェクトベースパス |
| `edgeExe` / `chromeExe` | ブラウザ実行ファイルパス |
| `defaultBrowser` | デフォルトブラウザ（`"edge"` または `"chrome"`） |
| `autoCleanup` | Linux側ポートの自動クリーンアップ有効/無効 |
| `statusline` | Statusline機能の詳細設定（各表示項目の有効/無効） |
| `claudeCode.env` | Claude Code実行時に設定される環境変数 |
| `claudeCode.settings` | Claude Codeのアプリケーション設定（`settings.json` にマージ） |

### 環境変数一覧（`claudeCode.env`）

| 環境変数 | 説明 |
|----------|------|
| `CLAUDE_CHROME_DEBUG_PORT` | DevToolsポート番号（run-claude.sh内で動的設定） |
| `MCP_CHROME_DEBUG_PORT` | MCPサーバー用DevToolsポート番号（run-claude.sh内で動的設定） |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | Agent Teams オーケストレーション機能の有効化（`1`で有効） |
| `ENABLE_TOOL_SEARCH` | ツール検索機能の有効化 |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | 自動コンパクト閾値のオーバーライド（パーセンテージ） |
| `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION` | プロンプト候補提示機能の有効化 |