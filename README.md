# agent-lab

実験・自動化スクリプト置き場。現在の主要機能: **Drive Sync**（GitHub → Google Drive 自動同期）。

---

## Drive Sync

GitHub Actions が `main` への push をトリガーに、Google Drive へファイルを自動同期する。
認証は OAuth 2.0（refresh token）方式。

### 構成図

```
GitHub Repository (main)
       |
       | push / workflow_dispatch
       v
GitHub Actions (.github/workflows/drive-sync.yml)
       |
       | 1. OAuth refresh token から access token を取得
       v
Google Drive API v3
       |
       | 2. latest/ と history/YYYY-MM/ へ書き込み
       v
Google Drive / agent-lab / drive-sync /
  ├── latest/          <- 最新 1 件（常に上書き）
  └── history/
      └── YYYY-MM/     <- 月単位アーカイブ（1 年保持）
```

### 認証方式（Drive Sync）

- `drive-sync.yml` は GitHub Secrets の OAuth 情報（`DRIVE_OAUTH_CLIENT_ID` / `DRIVE_OAUTH_CLIENT_SECRET` / `DRIVE_OAUTH_REFRESH_TOKEN`）で access token を取得して Drive API を呼び出す。
- `drive-retention.yml`（履歴削除）は別系統で WIF + OIDC を使用する。

### 実行トリガー

| トリガー | 条件 |
|---------|------|
| 自動 | `main` ブランチへの push |
| 手動 | Actions タブ → Drive Sync → Run workflow |

```bash
# CLI で手動実行
gh workflow run drive-sync.yml --ref main
gh run list --workflow=drive-sync.yml --limit 5
```

### 運用フロー

1. `main` へ push
2. `drive-sync.yml` が起動 → `scripts/drive-sync.sh` を実行
3. OAuth refresh token から access token を取得
4. Drive API で `latest/` を更新、`history/YYYY-MM/` にアーカイブ
5. `drive-retention.yml` で週次 dry-run、必要時のみ手動削除

詳細: [`runbooks/drive-sync.md`](runbooks/drive-sync.md) | [`runbooks/drive-history-retention.md`](runbooks/drive-history-retention.md)

### トラブルシュート早見表

| エラー | 原因 | 参照 |
|--------|------|------|
| OAuth token `invalid_client` | OAuth クライアント ID/シークレット不整合 | Runbook §401 |
| OAuth token `invalid_grant` | リフレッシュトークン失効・無効化 | Runbook §401 |
| Drive API `403` | Drive スコープ不足 / Drive API 未有効化 | Runbook §403 |
| Drive API `404` | `DRIVE_FOLDER_ID` が未設定または placeholder のまま | Runbook §404 |

詳細: [`runbooks/drive-sync.md`](runbooks/drive-sync.md)

---

## Standard PR Workflow

標準フロー（軽量運用）:

AI or Human -> feature branch -> edit -> git diff / status check -> commit -> push -> Pull Request -> human merge -> main

参照:

- [`docs/RUNBOOK-ai-pr-workflow.md`](docs/RUNBOOK-ai-pr-workflow.md)
- [`docs/RUNBOOK-drive-sync.md`](docs/RUNBOOK-drive-sync.md)
- [`docs/ADR-001-drive-sync-architecture.md`](docs/ADR-001-drive-sync-architecture.md)

---

## ファイル構成

```
.github/workflows/drive-sync.yml        - ワークフロー定義
.github/workflows/drive-retention.yml   - 履歴削除ワークフロー
scripts/drive-sync.sh                   - 同期スクリプト本体
scripts/drive-sync.config.env           - 非 Secret 設定値
docs/drive-sync/                        - Drive フォルダ構造定義・運用ルール
runbooks/drive-sync.md                  - 運用 Runbook
runbooks/drive-history-retention.md    - 履歴削除ポリシー
```
