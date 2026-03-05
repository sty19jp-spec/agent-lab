# agent-lab

実験・自動化スクリプト置き場。現在の主要機能: **Drive Sync**（GitHub → Google Drive 自動同期）。

---

## Drive Sync

GitHub Actions が `main` への push をトリガーに、Google Drive へファイルを自動同期する。
認証は Workload Identity Federation（OIDC）による鍵レス方式。

### 構成図

```
GitHub Repository (main)
       |
       | push / workflow_dispatch
       v
GitHub Actions (.github/workflows/drive-sync.yml)
       |
       | 1. GitHub OIDC エンドポイントへ ID Token 取得
       |    audience=//iam.googleapis.com/<WIF_PROVIDER>
       v
GCP Workload Identity Federation (github-pool / github-provider)
       |
       | 2. STS が ID Token を検証 → 短命 access token 発行
       |    (SA impersonation: drive-uploader@agent-lab-integrations)
       v
Google Drive API v3
       |
       | 3. ファイル書き込み
       v
Google Drive / agent-lab / drive-sync /
  ├── latest/          <- 最新 1 件（常に上書き）
  └── history/
      └── YYYY/
          └── YYYY-MM/ <- 月単位アーカイブ（1 年保持）
```

### 認証方式: WIF + OIDC（鍵レス）

サービスアカウントキー（JSON）は一切使用しない。
GitHub Actions の OIDC トークンを GCP Workload Identity Federation で交換し、
短命の access token を取得する。

詳細: [`runbooks/adr/ADR-DriveSync-WIF-OIDC.md`](runbooks/adr/ADR-DriveSync-WIF-OIDC.md)

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
3. WIF 認証 → access token 取得
4. Drive API で `latest/` を更新、`history/YYYY/YYYY-MM/` にアーカイブ
5. 年 1 回、1 年以上経過した `history/YYYY/` を手動削除

詳細: [`runbooks/drive-sync.md`](runbooks/drive-sync.md) | [`runbooks/drive-history-retention.md`](runbooks/drive-history-retention.md)

### トラブルシュート早見表

| エラー | 原因 | 参照 |
|--------|------|------|
| `invalid_grant: audience does not match` | OIDC audience の `//iam.googleapis.com/` プレフィクス不足 | ADR §OIDC Audience |
| Drive API `403` | Drive スコープ不足 / Drive API 未有効化 | Runbook §403 |
| Drive API `404` | `DRIVE_FOLDER_ID` が未設定または placeholder のまま | Runbook §404 |
| `missing ACTIONS_ID_TOKEN_REQUEST_URL` | `permissions: id-token: write` がない | Runbook §OIDC |

詳細: [`runbooks/drive-sync.md`](runbooks/drive-sync.md)

---

## ファイル構成

```
.github/workflows/drive-sync.yml        - ワークフロー定義
scripts/drive-sync.sh                   - 同期スクリプト本体
scripts/drive-sync.config.env           - 非 Secret 設定値
docs/drive-sync/                        - Drive フォルダ構造定義・運用ルール
runbooks/drive-sync.md                  - 運用 Runbook
runbooks/adr/ADR-DriveSync-WIF-OIDC.md - 設計決定記録（ADR）
runbooks/drive-history-retention.md    - 履歴削除ポリシー
```
