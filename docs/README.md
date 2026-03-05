# Drive Sync — システム概要

**Drive Sync** は GitHub リポジトリ (`agent-lab`) のファイルを Google Drive へ自動バックアップする仕組みです。
認証は **WIF（Workload Identity Federation）+ OIDC（OpenID Connect）** による鍵レス方式を採用しています。

> **用語定義**
> - **WIF**: GCP Workload Identity Federation — 外部 IdP のトークンを GCP access token に交換する仕組み
> - **OIDC**: OpenID Connect — GitHub Actions が発行する短命 ID Token の規格
> - **SA**: Service Account（GCP サービスアカウント）
> - **STS**: Security Token Service — GCP の token 交換エンドポイント
> - **CI**: Continuous Integration（GitHub Actions を指す）
> - **PR**: Pull Request

---

## 1. システム目的

GitHub `main` ブランチが唯一の Source of Truth（正本）です。
Google Drive バックアップはセカンダリコピーとして、GitHub 外部でのファイル参照・復旧に使用します。

---

## 2. アーキテクチャ図

```
┌─────────────────────────────────────────────────────────────────┐
│  GitHub Repository (agent-lab / main)                           │
│                                                                  │
│  push または workflow_dispatch                                   │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  GitHub Actions  (.github/workflows/drive-sync.yml)             │
│  job: upload                                                     │
│                                                                  │
│  Step 1: GitHub OIDC エンドポイントへ ID Token 要求              │
│          audience = //iam.googleapis.com/<WIF_PROVIDER>          │
└──────────────────────┬──────────────────────────────────────────┘
                       │ ID Token (JWT, 短命)
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  GCP Workload Identity Federation                                │
│  Pool: github-pool / Provider: github-provider                   │
│                                                                  │
│  Step 2: STS が ID Token を検証                                  │
│          → SA impersonation で短命 access token 発行             │
│             SA: drive-uploader@agent-lab-integrations            │
└──────────────────────┬──────────────────────────────────────────┘
                       │ access token（短命）
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  Google Drive API v3                                             │
│  https://www.googleapis.com/drive/v3/files                       │
│                                                                  │
│  Step 3: ファイル操作（読み取り / 書き込み）                     │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ▼
             Google Drive（バックアップ先）
```

---

## 3. データフロー

| フェーズ | 内容 |
|---------|------|
| トリガー | `main` への push または `workflow_dispatch`（手動） |
| 認証 | GitHub OIDC token → GCP WIF token 交換（鍵レス） |
| 書き込み先 | `latest/` を上書き、`history/YYYY-MM/` にアーカイブ |
| 現状 | `scripts/drive-sync.sh` は認証・疎通確認の skeleton。Drive 書き込みは未実装 |

---

## 4. Drive フォルダ構造

> **注意**: 以下は設計上の構造です。`drive-sync.sh` は現在 skeleton のため、実際の Drive フォルダはまだ作成されていません。

```
Google Drive
└── agent-lab
    └── drive-sync
        ├── latest/
        │   └── backup-latest.txt    ← 実行のたびに上書き（最新 1 件のみ）
        └── history/
            └── YYYY-MM/             ← 月単位アーカイブ（12 ヶ月保持）
                └── backup-YYYY-MM.txt
```

`latest/` は常に最新 1 件だけ保持し、`history/YYYY-MM/` に月単位のスナップショットを蓄積します。
12 ヶ月を超えた `history/YYYY-MM/` は Retention ワークフローで削除します。

---

## 5. 使用技術

| 技術 | 用途 |
|------|------|
| GitHub Actions | CI/CD ランナー。push / workflow_dispatch トリガー |
| GitHub OIDC | 短命 ID Token 発行（キーレス認証の起点） |
| GCP WIF | GitHub OIDC token を GCP access token に交換 |
| gcloud CLI | WIF cred config 生成・token 交換・Drive API 呼び出し |
| Google Drive API v3 | ファイルのアップロード・フォルダ操作 |
| Bash | スクリプト本体（`scripts/drive-sync.sh`, `scripts/drive-history-clean.sh`） |

---

## 6. GitHub Secret

| Secret 名 | 用途 |
|-----------|------|
| `DRIVE_FOLDER_ID` | Google Drive のバックアップ先フォルダ ID |

`GCP_WIF_PROVIDER` と `GCP_SERVICE_ACCOUNT` は Secret ではなく、
リポジトリ内 `scripts/drive-sync.config.env` に非機密設定として保存されています。

---

## 7. セットアップ概要

詳細な手順は [RUNBOOK-drive-sync.md](RUNBOOK-drive-sync.md) を参照してください。
設計判断の根拠は [ADR-001-drive-sync-architecture.md](ADR-001-drive-sync-architecture.md) を参照してください。

大枠の前提:

1. GCP プロジェクト `agent-lab-integrations` に WIF Pool / Provider が設定済み
2. SA `drive-uploader@agent-lab-integrations.iam.gserviceaccount.com` が Drive API 権限を持つ
3. GitHub Secret `DRIVE_FOLDER_ID` にバックアップ先フォルダ ID が登録済み
4. `scripts/drive-sync.config.env` に `GCP_WIF_PROVIDER` と `GCP_SERVICE_ACCOUNT` が設定済み

---

## 8. リポジトリ構成

```
.github/workflows/
  drive-sync.yml          ← 同期ワークフロー（push / workflow_dispatch）
  drive-retention.yml     ← 履歴削除ワークフロー（weekly schedule / workflow_dispatch）

scripts/
  drive-sync.sh           ← 同期スクリプト本体（現在 skeleton）
  drive-history-clean.sh  ← 履歴削除スクリプト
  drive-sync.config.env   ← 非 Secret 設定（WIF Provider / SA email）

docs/
  README.md               ← 本ファイル（初見向け概要）
  RUNBOOK-drive-sync.md   ← 運用手順書
  ADR-001-drive-sync-architecture.md ← 設計決定記録

runbooks/
  drive-sync.md           ← 旧 Runbook（参考）
  drive-history-retention.md ← 履歴削除ポリシー詳細
  adr/ADR-DriveSync-WIF-OIDC.md ← 旧 ADR（参考）
```
