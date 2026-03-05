# RUNBOOK: Drive Sync 運用手順書

対象システム: `agent-lab` Drive Sync
対象読者: 運用担当者・引継ぎ担当者・AIエージェント

> **前提知識**
> - WIF（Workload Identity Federation）= 外部 IdP トークンを GCP access token に交換する仕組み
> - OIDC（OpenID Connect）= GitHub Actions が発行する短命 ID Token の規格
> - workflow_dispatch = GitHub Actions の手動実行トリガー

---

## 1. ワークフロー一覧

| ワークフロー名 | ファイル | トリガー | 用途 |
|--------------|---------|---------|------|
| Drive Sync (latest + history) | `.github/workflows/drive-sync.yml` | `main` push / workflow_dispatch | ファイル同期 |
| Drive History Retention | `.github/workflows/drive-retention.yml` | schedule（毎週日曜 02:00 UTC）/ workflow_dispatch | 履歴削除 |

---

## 2. Drive Sync の手動実行

### 2-1. GitHub UI

```
1. リポジトリの Actions タブを開く
2. 左サイドバーから "Drive Sync (latest + history)" を選択
3. "Run workflow" → Branch: main → "Run workflow" をクリック
```

### 2-2. CLI（gh コマンド）

```bash
# 実行
gh workflow run drive-sync.yml --repo sty19jp-spec/agent-lab --ref main

# 状態確認（最新 5 件）
gh run list --repo sty19jp-spec/agent-lab --workflow="Drive Sync (latest + history)" --limit 5

# ログ全件表示
gh run view <RUN_ID> --repo sty19jp-spec/agent-lab --log

# 失敗ステップのみ
gh run view <RUN_ID> --repo sty19jp-spec/agent-lab --log-failed
```

---

## 3. ログ確認ポイント

成功時のログは以下の順序で出力される。**各行が出力されているか**を確認する。

```
[TIMESTAMP] Fetching GitHub OIDC token...
[TIMESTAMP] Creating WIF credential config...
Created credential configuration file [.../wif-cred.json].
[TIMESTAMP] Activating gcloud auth with WIF cred file...
Authenticated with external account credentials for: drive-uploader@agent-lab-integrations.iam.gserviceaccount.com.
[TIMESTAMP] Checking access token...
WARNING: `--scopes` flag may not work as expected ...   ← 既知の警告。無視してよい
[TIMESTAMP] Drive API connectivity check...
[TIMESTAMP] OK: WIF auth + access token + Drive API connectivity passed (skeleton).
```

### ステップ対応表

| ログ行 | 確認ポイント |
|--------|------------|
| `Fetching GitHub OIDC token...` | OIDC token 取得開始 |
| `Created credential configuration file` | WIF cred config 生成成功 |
| `Authenticated with external account credentials for: drive-uploader@...` | gcloud 認証成功 |
| `Drive API connectivity check...` | Drive API 疎通開始 |
| `OK: WIF auth + access token + Drive API connectivity passed (skeleton).` | **成功確認行** |

> **現状**: `drive-sync.sh` は認証・疎通確認の skeleton です。
> Drive へのファイル書き込みは未実装のため、上記ログで終了するのが正常です。

---

## 4. トラブルシュート

失敗時は以下のフローで切り分ける。

```
gh run view <RUN_ID> --log-failed でログ確認
        │
        ├── "invalid_grant" または "audience does not match"  →  § 4-1
        ├── "403 Forbidden"                                    →  § 4-2
        ├── "404 Not Found"                                    →  § 4-3
        ├── "missing ACTIONS_ID_TOKEN_REQUEST_URL"             →  § 4-4
        └── それ以外                                          →  § 4-5
```

### 4-1. `invalid_grant: The audience in ID Token does not match`

**原因**: OIDC token の audience が `//iam.googleapis.com/` プレフィクスなしで発行されている。

**確認**:
```bash
grep "audience=" scripts/drive-sync.sh
# 期待値: audience=//iam.googleapis.com/${GCP_WIF_PROVIDER}
```

**対処**: `//iam.googleapis.com/` プレフィクスが含まれていない場合は `drive-sync.sh` を修正する。

詳細: `docs/ADR-001-drive-sync-architecture.md` § Pitfall 1

---

### 4-2. `403 Forbidden` (Drive API)

**原因**: Drive API が GCP プロジェクトで有効化されていない、または SA に Drive 権限がない。

**確認**:
```bash
# GCP 側: Drive API 有効化確認
gcloud services list --project=agent-lab-integrations | grep drive
# 期待値: drive.googleapis.com  Google Drive API  enabled

# SA の IAM 権限確認
gcloud projects get-iam-policy agent-lab-integrations \
  --flatten="bindings[].members" \
  --filter="bindings.members:drive-uploader"
```

**対処**: Drive API が無効の場合は `gcloud services enable drive.googleapis.com --project=agent-lab-integrations`。

---

### 4-3. `404 Not Found` (Drive API)

**原因**: `DRIVE_FOLDER_ID` が未設定、または placeholder のまま。

**確認**:
```bash
# Secret の登録確認
gh secret list --repo sty19jp-spec/agent-lab
# DRIVE_FOLDER_ID が一覧にあるか確認

# workflow の env 注入確認
grep -A2 "run: bash scripts/drive-sync.sh" .github/workflows/drive-sync.yml
# env: DRIVE_FOLDER_ID: ${{ secrets.DRIVE_FOLDER_ID }} があるか
```

**対処**: Secret が未登録の場合は GitHub Settings → Secrets → `DRIVE_FOLDER_ID` を設定する。

---

### 4-4. `missing ACTIONS_ID_TOKEN_REQUEST_URL`

**原因**: ワークフローの `permissions` から `id-token: write` が失われている。

**確認と対処**:
```yaml
# .github/workflows/drive-sync.yml に以下が必須
permissions:
  contents: read
  id-token: write   ← これがないと OIDC token を取得できない
```

> **Note:**
> `actions: read` permission is not required for this workflow.
> It should only be added if the workflow needs to call the GitHub
> Actions API (for example via `gh api`, `gh run list`, or other
> Actions metadata queries).

---

### 4-5. GCP 側の確認コマンド

```bash
PROJECT=agent-lab-integrations
POOL=github-pool
PROVIDER=github-provider

# WIF Pool 確認
gcloud iam workload-identity-pools describe ${POOL} \
  --project=${PROJECT} --location=global

# WIF Provider 確認
gcloud iam workload-identity-pools providers describe ${PROVIDER} \
  --workload-identity-pool=${POOL} \
  --project=${PROJECT} --location=global

# SA バインディング確認
gcloud projects get-iam-policy ${PROJECT} \
  --flatten="bindings[].members" \
  --filter="bindings.members:drive-uploader"
```

---

## 5. Drive フォルダ構造

```
Google Drive
└── agent-lab
    └── drive-sync
        ├── latest/
        │   └── backup-latest.txt    ← 実行のたびに上書き（最新 1 件のみ）
        └── history/
            └── YYYY-MM/             ← 月単位アーカイブ（12 ヶ月保持）
```

- `latest/` は常に最新 1 件のみ保持。
- `history/YYYY-MM/` は `drive-history-clean.sh` が直接参照する命名規則。

---

## 6. Retention（履歴削除）

保持期間: **12 ヶ月**。12 ヶ月より古い `history/YYYY-MM/` が削除対象。

### 安全段階

```
Stage 1: dry-run（デフォルト / schedule は常にこちら）
  → 削除対象の YYYY-MM 名と Drive フォルダ ID をログ出力するだけ
  → 何も削除しない

Stage 2: confirm + delete（workflow_dispatch で明示入力時のみ）
  → confirm_delete=yes かつ schedule 実行でない場合のみ削除
  → デフォルトはゴミ箱移動（30 日後に自動消去）
  → hard_delete=yes を追加した場合のみ即時完全削除（復元不可）
```

### 手動実行手順

**手順 A: dry-run で削除候補を確認する（まず必ずここから）**

```
1. Actions → Drive History Retention → Run workflow
2. retain_months: 12
3. confirm_delete: （空欄）
4. hard_delete: （空欄）
5. Run workflow
→ ログに削除候補が出力される。削除はしない。
```

**手順 B: ゴミ箱移動（通常削除）**

```
1. 手順 A で対象フォルダをログで確認する
2. Actions → Drive History Retention → Run workflow
3. retain_months: 12
4. confirm_delete: yes
5. hard_delete: （空欄）
6. Run workflow
→ 対象フォルダが Drive ゴミ箱へ移動（30 日後に自動消去）
```

**手順 C: 即時完全削除（復元不可）**

```
1. 手順 A で対象フォルダをログで確認する
2. Actions → Drive History Retention → Run workflow
3. retain_months: 12
4. confirm_delete: yes
5. hard_delete: yes
6. Run workflow
→ 対象フォルダが即時完全削除
```

---

## 7. 復旧手順

> **前提**: GitHub `main` が正本です。Drive は補助バックアップです。

### 7-1. latest から最新ファイルを取得する

```
1. Google Drive を開く
2. agent-lab/drive-sync/latest/ を開く
3. backup-latest.txt をダウンロードする
```

### 7-2. history から特定時点のファイルを取得する

```
1. Google Drive を開く
2. agent-lab/drive-sync/history/YYYY-MM/ を開く
   例: history/2026-02/ → 2026 年 2 月時点のバックアップ
3. 対象ファイルをダウンロードする
```

---

## 8. Secrets と設定ファイル

| 名前 | 保管場所 | 用途 |
|------|----------|------|
| `DRIVE_FOLDER_ID` | GitHub Secrets | Drive バックアップ先フォルダ ID（機密）|
| `GCP_WIF_PROVIDER` | `scripts/drive-sync.config.env`（リポジトリ内） | WIF プロバイダリソース名 |
| `GCP_SERVICE_ACCOUNT` | `scripts/drive-sync.config.env`（リポジトリ内） | SA メールアドレス |

**境界ルール**:
- `DRIVE_FOLDER_ID` は GitHub Secret のみに保存する。`config.env` には書かない。
- `GCP_WIF_PROVIDER` / `GCP_SERVICE_ACCOUNT` はリポジトリに平文で保存する（機密情報ではない）。
- ワークフローは `env: DRIVE_FOLDER_ID: ${{ secrets.DRIVE_FOLDER_ID }}` で Secret を注入する。
  `config.env` の条件付き代入 `${DRIVE_FOLDER_ID:-...}` により、Secret が優先される。

---

## 9. 確認済みの動作 Run

| Run ID | 日時 (UTC) | トリガー | 結果 |
|--------|-----------|---------|------|
| 22709627994 | 2026-03-05T08:43Z | workflow_dispatch | success |
| 22707839837 | 2026-03-05T07:51Z | push | success |
| 22701686259 | 2026-03-05T04:03Z | push | success |

---

## 10. 関連ドキュメント

| ファイル | 内容 |
|---------|------|
| `docs/README.md` | システム概要・アーキテクチャ図 |
| `docs/ADR-001-drive-sync-architecture.md` | 設計決定記録（WIF 採用理由等） |
| `runbooks/drive-history-retention.md` | 履歴削除ポリシー詳細 |
