# Drive Sync — システム概要

`agent-lab` の Google Drive バックアップ運用は、用途の異なる 2 つのワークフローで構成されています。

- **Drive Sync**: リポジトリ内容を `latest/` と `history/YYYY-MM/` に同期
- **Drive History Retention**: 古い `history/YYYY-MM/` を保持ポリシーに基づき削除

---

## 1. システム目的

GitHub `main` を Source of Truth とし、Google Drive は運用バックアップとして使用する。
実運用では、`main` への更新（push）を同期処理の基本トリガーとする。

---

## 2. 認証と役割の整理

| ワークフロー | 主目的 | 認証方式 |
|---|---|---|
| `.github/workflows/drive-sync.yml` | 最新 + 月次アーカイブのアップロード | **OAuth 2.0 refresh token** |
| `.github/workflows/drive-retention.yml` | 古い履歴フォルダの削除（週次 dry-run / 手動 delete） | **WIF + GitHub OIDC** |

補足:
- `drive-sync.sh` は OAuth access token を取得して Drive API を実行する。
- `drive-history-clean.sh` は OIDC token と WIF を使って access token を取得する。

---

## 3. データフロー（Drive Sync）

1. `main` への push または `workflow_dispatch`
2. `scripts/drive-sync.sh` がアーカイブを作成
3. OAuth refresh token から access token を取得
4. Drive API で以下を更新
   - `latest/backup-latest.tar.gz`
   - `history/YYYY-MM/backup-YYYY-MM.tar.gz`

---

## 4. Drive フォルダ構造

```
Google Drive
└── <DRIVE_FOLDER_ID のルート>
    ├── latest/
    │   └── backup-latest.tar.gz
    └── history/
        └── YYYY-MM/
            └── backup-YYYY-MM.tar.gz
```

`latest/` は常に 1 件を上書きし、`history/YYYY-MM/` は月次アーカイブを蓄積する。

---

## 5. 設定情報の整理

### Drive Sync で使用する GitHub Secrets

- `DRIVE_OAUTH_CLIENT_ID`
- `DRIVE_OAUTH_CLIENT_SECRET`
- `DRIVE_OAUTH_REFRESH_TOKEN`
- `DRIVE_FOLDER_ID`

### Retention で使用する主な設定

- GitHub Secret: `DRIVE_FOLDER_ID`
- 非Secret設定: `scripts/drive-sync.config.env`
  - `GCP_WIF_PROVIDER`
  - `GCP_SERVICE_ACCOUNT`

---

## 6. 関連ファイル

```
.github/workflows/
  drive-sync.yml          # 同期ワークフロー（push / workflow_dispatch）
  drive-retention.yml     # 履歴削除ワークフロー（schedule / workflow_dispatch）

scripts/
  drive-sync.sh           # 同期スクリプト（OAuth）
  drive-history-clean.sh  # 履歴削除スクリプト（WIF + OIDC）
  drive-sync.config.env   # 非 Secret 設定

runbooks/
  drive-sync.md               # Drive Sync 運用
  drive-history-retention.md  # Retention 運用
```

---

## 7. 参照先

- 運用手順: `runbooks/drive-sync.md`
- 保持/削除手順: `runbooks/drive-history-retention.md`
- 設計背景（参考）: `docs/ADR-001-drive-sync-architecture.md`
