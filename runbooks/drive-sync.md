# Drive Sync 運用 Runbook

---

## Scope

この Runbook は **`.github/workflows/drive-sync.yml`（OAuth 認証）** を対象とする。
`drive-retention.yml`（履歴削除）は認証方式が異なるため、`runbooks/drive-history-retention.md` を参照する。

---

## Architecture

```
GitHub
  |
  | push / workflow_dispatch
  v
GitHub Actions
  |
  | secrets: DRIVE_OAUTH_CLIENT_ID / SECRET / REFRESH_TOKEN
  v
OAuth2 token endpoint (oauth2.googleapis.com/token)
  |
  | access_token (short-lived)
  v
Google Drive API v3
  (POST /upload/drive/v3/files?uploadType=multipart)
  |
  v
Drive upload → latest/ + history/YYYY-MM/
```

関連ファイル:
- ワークフロー: `.github/workflows/drive-sync.yml`
- スクリプト: `scripts/drive-sync.sh`
- Retention Runbook: `runbooks/drive-history-retention.md`

---

## Secrets

| Secret 名 | 保管場所 | 用途 |
|-----------|----------|------|
| `DRIVE_OAUTH_CLIENT_ID` | GitHub Secrets | OAuth クライアント ID |
| `DRIVE_OAUTH_CLIENT_SECRET` | GitHub Secrets | OAuth クライアントシークレット |
| `DRIVE_OAUTH_REFRESH_TOKEN` | GitHub Secrets | OAuth リフレッシュトークン（長期） |
| `DRIVE_FOLDER_ID` | GitHub Secrets | Google Drive アップロード先フォルダ ID |

**境界ルール**:
- 4 つの Secret はすべて GitHub Secrets に保管。`config.env` はローカル開発用フォールバックのみ。
- ワークフローの `env:` ブロックで各 Secret を注入することで、`config.env` による上書きを防いでいる。
- リフレッシュトークンの対象プロジェクト: `agent-lab-integrations-489319`（project number: 266557062033）。Drive API はこのプロジェクトで有効化済み。

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

## 成功ログ例

```
[...] Obtaining OAuth access token...
[...] Creating archive (excluding .git, .claude, .drive-sync-out)...
[...] Resolving latest/ folder...
[...] Uploading backup-latest.tar.gz...
[...] Drive upload HTTP=200 (backup-latest.tar.gz)
[...] Uploaded latest: <FILE_ID>
[...] Resolving history/ folder...
[...] Resolving history/YYYY-MM/ folder...
[...] Uploading backup-YYYY-MM.tar.gz...
[...] Drive upload HTTP=200 (backup-YYYY-MM.tar.gz)
[...] Uploaded history/YYYY-MM: <FILE_ID>
[...] Drive Sync complete. latest=<ID>  history/YYYY-MM=<ID>
```

---

## 障害確認方法

### 1. 切り分け手順

```
失敗 run を確認
  |
  +-- gh run view <RUN_ID> --log-failed
        |
        +-- HTTP 400 / curl (22)  -> §400 upload error
        +-- "invalid_grant"       -> §401 token error
        +-- "403"                 -> §403 permission error
        +-- "404"                 -> §Drive API 404
        +-- それ以外              -> ログ全件を確認
```

---

### HTTP 400 upload error

multipart リクエストが不正、または親フォルダ ID が破損している。

チェック:
1. `gh run view <RUN_ID> --log` で `Drive upload error body:` 直後の JSON を確認
2. `history/YYYY-MM/ id:` の値が正常な Drive ID（33 文字英数字）かを確認
   - ログメッセージが混入している場合、`drive_find_or_create_folder` の stdout 汚染が原因
3. スクリプトの `log` 呼び出しが command substitution 内で `>&2` にリダイレクトされているか確認

```bash
grep -n 'log.*>&2' scripts/drive-sync.sh
```

---

### 401 / `invalid_grant` token error

リフレッシュトークンが失効しているか、クライアント ID/シークレットが間違っている。

チェック:
1. OAuth クライアントが `agent-lab-integrations-489319` に存在するか確認
2. GitHub Secrets の 3 つの OAuth 値が最新かを確認
3. ローカルでトークン再取得:

```bash
# get_refresh_token.py でトークンを再取得し、Secrets を更新する
python3 get_refresh_token.py
```

---

### 403 permission error

Drive API が無効か、OAuth スコープが不足している。

```bash
# Drive API 有効化確認（OAuth クライアントのプロジェクト）
gcloud services list --enabled \
  --project=agent-lab-integrations-489319 \
  --filter="name:drive.googleapis.com" \
  --format="value(name)"

# 無効な場合は有効化
gcloud services enable drive.googleapis.com \
  --project=agent-lab-integrations-489319
```

OAuth スコープ確認: リフレッシュトークン取得時に `https://www.googleapis.com/auth/drive` が含まれているか確認。

---

### Drive API `404`

`DRIVE_FOLDER_ID` が不正または親フォルダが別アカウントに存在する。

チェック:
1. `gh secret list` で `DRIVE_FOLDER_ID` が登録されているか
2. Google Drive UI でフォルダ URL の末尾 ID と Secret の値が一致するか
3. OAuth 認証アカウントがそのフォルダに編集権限を持っているか

---

## Drive フォルダ構成

```
Google Drive
└── <DRIVE_FOLDER_ID のルートフォルダ>
    ├── latest/              <- 常に最新 1 件のみ（実行のたびに trash → 再作成）
    │   └── backup-latest.tar.gz
    └── history/
        └── YYYY-MM/         <- 月単位アーカイブ（実行月ごとに自動作成）
            └── backup-YYYY-MM.tar.gz
```

保持ポリシー: `runbooks/drive-history-retention.md`

---

## Autonomous Operation

Claude Code が人手を介さず Drive Sync を完結させるための実行ループ。

### 実行ループ

```
gh workflow run drive-sync.yml
  ↓
gh run watch <RUN_ID>   # 完了まで待機
  ↓
gh run view <RUN_ID> --log   # ログ確認
  ↓
問題があれば最小限の修正を加えて
  ↓
git commit && git push
  ↓
再実行（ループ先頭へ）
```

### コマンド早見表

```bash
# ワークフロー起動
gh workflow run drive-sync.yml --ref main

# 最新 RUN_ID 取得
gh run list --workflow=drive-sync.yml -L 1 --json databaseId -q '.[0].databaseId'

# 完了まで待機（終了コードで成否判定）
gh run watch <RUN_ID> --exit-status

# ログ確認
gh run view <RUN_ID> --log
gh run view <RUN_ID> --log-failed   # 失敗ステップのみ

# ヘルパースクリプト（起動 + 待機を一括）
bash scripts/drive-sync-run.sh
```

---

## 成功確認済みラン

| Run ID | 日時 | トリガー |
|--------|------|---------|
| 22738463895 | 2026-03-05T21:52Z | workflow_dispatch（OAuth multipart fix 後） |
| 22707839837 | 2026-03-05T07:51Z | push（docs 追加コミット） |
| 22701686259 | 2026-03-05T04:03Z | push（PR #2 マージ） |
