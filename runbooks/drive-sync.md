# Drive Sync 運用 Runbook

---

## Architecture

```
GitHub Actions Runner
       |
       | ACTIONS_ID_TOKEN_REQUEST_URL へ audience 付きで OIDC token 取得
       v
GitHub OIDC エンドポイント
       |
       | ID Token (JWT, 短命)
       v
GCP WIF: gcloud iam workload-identity-pools create-cred-config
       |
       | 外部アカウント credential config JSON 生成
       v
gcloud auth login --cred-file → STS による token 交換
       |
       | 短命 access token（SA: drive-uploader）
       v
Drive API v3 (https://www.googleapis.com/drive/v3/files)
       |
       v
Google Drive / agent-lab / drive-sync / latest/ + history/
```

関連ファイル:
- ワークフロー: `.github/workflows/drive-sync.yml`
- スクリプト: `scripts/drive-sync.sh`
- 設計決定: `runbooks/adr/ADR-DriveSync-WIF-OIDC.md`

---

## Secrets

| Secret 名 | 保管場所 | 用途 |
|-----------|----------|------|
| `GCP_WIF_PROVIDER` | GitHub Secrets | WIF プロバイダリソース名（`projects/…/providers/…`） |
| `GCP_SERVICE_ACCOUNT` | GitHub Secrets | サービスアカウントメール |
| `DRIVE_FOLDER_ID` | GitHub Secrets | Google Drive フォルダ ID |

**境界ルール**:
- `GCP_WIF_PROVIDER` / `GCP_SERVICE_ACCOUNT` は `scripts/drive-sync.config.env` にも同値が存在するが、Secret が正とする。
- `DRIVE_FOLDER_ID` は **Secret のみ**。`config.env` の `PASTE_DRIVE_FOLDER_ID_HERE` はローカル開発時のフォールバック表示であり、CI では使用されない。
- ワークフローの `env:` ブロックで `DRIVE_FOLDER_ID: ${{ secrets.DRIVE_FOLDER_ID }}` として注入することで、`config.env` の source による上書きを防いでいる。

---

## 自動実行

| 項目 | 値 |
|------|----|
| トリガー | `main` ブランチへの push |
| ワークフロー | `.github/workflows/drive-sync.yml` |
| ジョブ | `upload` |
| 実行履歴 | Actions タブ → Drive Sync (latest + history) |

---

## 手動実行方法

**GitHub UI**: Actions → Drive Sync (latest + history) → Run workflow → Branch: `main`

**CLI**:
```bash
gh workflow run drive-sync.yml --ref main
gh run list --workflow=drive-sync.yml --limit 5   # 実行状況確認
gh run view <RUN_ID> --log                         # ログ全件
gh run view <RUN_ID> --log-failed                  # 失敗ステップのみ
```

---

## 障害確認方法

### 1. 切り分け手順

```
失敗 run を確認
  |
  +-- gh run view <RUN_ID> --log-failed
        |
        +-- "invalid_grant"       -> §OIDC audience
        +-- "403"                 -> §Drive API 403
        +-- "404"                 -> §Drive API 404
        +-- "missing ACTIONS_"   -> §OIDC 権限
        +-- それ以外              -> §GCP 側確認
```

### `invalid_grant: audience does not match`

OIDC token の audience が `//iam.googleapis.com/` プレフィクスなしで発行されている。

```bash
grep "audience=" scripts/drive-sync.sh
# 期待値: audience=//iam.googleapis.com/${GCP_WIF_PROVIDER}
```

詳細は `runbooks/adr/ADR-DriveSync-WIF-OIDC.md` §OIDC Audience を参照。

---

### Drive API `403`

access token が Drive スコープを含まない、または Drive API が GCP で無効。

```bash
# スクリプトの access token 取得行を確認
grep "print-access-token" scripts/drive-sync.sh
# 期待値: --scopes=https://www.googleapis.com/auth/drive.readonly

# GCP 側: Drive API 有効化確認
gcloud services list --project=agent-lab-integrations | grep drive
```

---

### Drive API `404`

`DRIVE_FOLDER_ID` が placeholder のまま渡されている。

チェック:
1. `gh secret list` で `DRIVE_FOLDER_ID` が登録されているか
2. `.github/workflows/drive-sync.yml` の step に `env: DRIVE_FOLDER_ID: ${{ secrets.DRIVE_FOLDER_ID }}` があるか

---

### `missing ACTIONS_ID_TOKEN_REQUEST_URL`

ワークフローの `permissions` から `id-token: write` が失われている。

```yaml
# .github/workflows/drive-sync.yml に必須
permissions:
  contents: read
  id-token: write
```

---

### GCP 側の確認コマンド

```bash
PROJECT=agent-lab-integrations
POOL=github-pool
PROVIDER=github-provider

# WIF Pool / Provider 確認
gcloud iam workload-identity-pools describe ${POOL} \
  --project=${PROJECT} --location=global
gcloud iam workload-identity-pools providers describe ${PROVIDER} \
  --workload-identity-pool=${POOL} --project=${PROJECT} --location=global

# SA へのバインディング確認
gcloud projects get-iam-policy ${PROJECT} \
  --flatten="bindings[].members" \
  --filter="bindings.members:drive-uploader"
```

---

## Drive フォルダ構成

```
Google Drive
└── agent-lab
    └── drive-sync
        ├── latest/          <- 常に最新 1 件のみ（実行のたびに上書き）
        └── history/
            └── YYYY/
                └── YYYY-MM/ <- 月単位アーカイブ（1 年保持後削除対象）
```

詳細: `docs/drive-sync/drive-folder-structure.md`
保持ポリシー: `runbooks/drive-history-retention.md`

---

## 成功確認済みラン

| Run ID | 日時 | トリガー |
|--------|------|---------|
| 22707839837 | 2026-03-05T07:51Z | push（docs 追加コミット） |
| 22701686259 | 2026-03-05T04:03Z | push（PR #2 マージ） |
