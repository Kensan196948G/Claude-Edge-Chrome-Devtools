# ネットワークドライブ恒久解決策ドキュメント

## 問題の概要

PowerShell 7 (pwsh) から Windows のマップドネットワークドライブ（X:\ 等）にアクセスできない問題に対する恒久的な解決策を実装しました。

## 根本原因

### なぜ pwsh からドライブが見えないのか？

1. **セッション分離**: `cmd.exe` → `pwsh` で起動すると、新しいプロセス空間で動作します
2. **マッピングのスコープ**: Windows Explorer や `net use` で作成したドライブマッピングは、元のセッションにのみ有効
3. **PSDrive の非永続性**: PowerShell 5.1 と PowerShell 7 ではドライブの扱いが異なります

## 実装した恒久解決策

### 1. UNC パスの config.json への追加

```json
{
  "zDrive": "X:\\",
  "zDriveUncPath": "\\\\kensan1969\\LinuxHDD"
}
```

- `zDrive`: ドライブレター（従来通り）
- `zDriveUncPath`: **UNC パス（新規追加）** - ドライブレターに依存しない絶対パス

### 2. 4段階フォールバック機構

スクリプトは以下の順序でプロジェクトルートへのアクセスを試行します：

```
ステップ1: ドライブレター直接アクセス試行 (X:\)
    ↓ 失敗
ステップ2: UNC パス取得
    2-1: config.json の zDriveUncPath から取得 ← ★最優先★
    2-2: レジストリ (HKCU:\Network\X) から取得
    2-3: SMB マッピングから取得
    2-4: 既存 PSDrive から取得
    ↓ いずれかで成功
ステップ3: ドライブマッピング作成
    New-PSDrive -Name X -Root <UNCパス> -Scope Global
    ↓ 成功 or 失敗
ステップ4: パス決定
    - マッピング成功 → X:\ を使用
    - マッピング失敗 → UNC パスを直接使用
```

### 3. `$ProjectRootPath` 変数の導入

従来:
```powershell
$ZRoot = "X:\"
$Projects = Get-ChildItem $ZRoot -Directory
```

変更後:
```powershell
$ProjectRootPath = "X:\"  # または "\\kensan1969\LinuxHDD"
$Projects = Get-ChildItem $ProjectRootPath -Directory
```

- `$ProjectRootPath`: ドライブレターまたは UNC パスのいずれかを保持
- すべてのファイル操作で `$ProjectRootPath` を使用
- ドライブレターが使えなくても UNC パスで動作継続

## 動作フロー図

```
開始
  │
  ├─ X:\ にアクセス可能？
  │   ├─ YES → $ProjectRootPath = "X:\"
  │   └─ NO  → UNC パス取得へ
  │             │
  │             ├─ config.json から取得？
  │             │   ├─ YES → UNC = "\\kensan1969\LinuxHDD"
  │             │   └─ NO  → 次の方法へ
  │             │
  │             ├─ レジストリから取得？
  │             ├─ SMB マッピングから取得？
  │             └─ PSDrive から取得？
  │                 │
  │                 ├─ 取得成功 → ドライブマッピング作成
  │                 │              │
  │                 │              ├─ 成功 → $ProjectRootPath = "X:\"
  │                 │              └─ 失敗 → $ProjectRootPath = UNC パス
  │                 │
  │                 └─ 取得失敗 → エラー
  │
  └─ $ProjectRootPath でプロジェクト一覧取得
```

## 利点

### ドライブレターに依存しない

- ドライブレターが変更されても UNC パスで動作
- 複数ユーザー・複数マシンで異なるドライブレターを使用可能

### セッション間の安定性

- pwsh セッションごとにドライブマッピングを再作成
- マッピングが失われても UNC パスで継続

### 診断情報の充実

エラー時に以下を表示：
- 試行したドライブレター
- 検出された UNC パス
- 現在の PSDrive 一覧
- 最終的に使用したパス

## 設定例

### 単一マシン環境

```json
{
  "zDrive": "X:\\",
  "zDriveUncPath": "\\\\192.168.0.185\\LinuxHDD"
}
```

### 複数マシン環境（ホスト名使用）

```json
{
  "zDrive": "X:\\",
  "zDriveUncPath": "\\\\linuxserver\\projects"
}
```

### ドライブレター不使用（UNCパスのみ）

```json
{
  "zDrive": "\\\\linuxserver\\projects",
  "zDriveUncPath": "\\\\linuxserver\\projects"
}
```

この場合、ドライブマッピングは試行されず、常に UNC パスが使用されます。

## トラブルシューティング

### エラー: "UNC パスが見つかりません"

**原因**: `config.json` に `zDriveUncPath` が設定されておらず、他の方法でも UNC パスを検出できない

**解決策**: `config.json` に以下を追加
```json
"zDriveUncPath": "\\\\<サーバー名またはIP>\\<共有名>"
```

### エラー: "UNC パスにアクセスできません"

**原因**: ネットワーク接続の問題、または共有フォルダの権限不足

**確認手順**:
1. エクスプローラーから UNC パスにアクセスできるか確認
2. `ping <サーバー名>` でネットワーク接続確認
3. SMB共有の権限を確認

### ドライブマッピングが作成されない

**原因**: `-Persist` フラグには管理者権限が必要な場合があります（Windows のバージョンによる）

**影響**: なし。マッピング失敗時は自動的に UNC パスを直接使用します

## パフォーマンス考慮

- **UNC パス直接使用**: ドライブレター経由と比較して、わずかにパス解決のオーバーヘッドがあります（通常は体感できないレベル）
- **推奨**: できるだけドライブマッピングを作成し、ドライブレター経由でアクセスする方が高速です
- スクリプトは自動的に最適な方法を選択します

## 今後の保守

### config.json の管理

- **バージョン管理**: `config.json` はリポジトリにコミットできます（GitHub Token は Base64 エンコード済み）
- **環境依存値**: マシンごとに異なる場合は、`config.local.json` に分離することも検討可能

### 定期的な確認

以下のコマンドで現在のマッピング状態を確認できます：

```powershell
# PowerShell から確認
Get-SmbMapping
Get-PSDrive -PSProvider FileSystem | Where-Object Name -match "^[X-Z]$"

# UNC パス直接アクセステスト
Test-Path "\\kensan1969\LinuxHDD"
```
