# ADR: GitHub Actions → Google Drive 同期（WIF / OIDC 鍵レス認証）

## ステータス: 採用・実装完了

最終確認 run: 22701686259（2026-03-05）

---

## 背景

GitHub Actions から Google Drive へファイルをアップロードする定期同期が必要。
従来の GCP サービスアカウントキー（JSON）をリポジトリ Secret に保存する方式は
鍵の漏洩リスク・ローテーション運用コストが高いため採用しない。

---

## 決定: Workload Identity Federation（OIDC 鍵レス）を採用

GitHub Actions の OIDC 機能と GCP Workload Identity Federation を連携させ、
短命トークン（ID Token）のみで GCP リソースへアクセスする。
サービスアカウントキーは一切使用しない。

---

## 認証フロー

```
GitHub Actions Runner
  |
  +-1-> GitHub OIDC エンドポイント（ACTIONS_ID_TOKEN_REQUEST_URL）へ
  |      audience=//iam.googleapis.com/<WIF_PROVIDER> で ID Token 取得
  |
  +-2-> gcloud iam workload-identity-pools create-cred-config
  |      -> 外部アカウント credential config JSON を生成
  |
  +-3-> gcloud auth login --cred-file=<config.json>
  |      -> STS（Security Token Service）が ID Token を検証・交換
  |      -> SA impersonation で短命 access token 発行
  |
  +-4-> Drive API v3 呼び出し（Bearer access token）
```

---

## 重要な実装上の注意点

### OIDC Audience は `//iam.googleapis.com/` プレフィクスが必須

```bash
# NG: bare resource path -> invalid_grant エラー
audience=${GCP_WIF_PROVIDER}
# -> projects/147807620986/.../github-provider

# OK: full URI form
audience=//iam.googleapis.com/${GCP_WIF_PROVIDER}
# -> //iam.googleapis.com/projects/147807620986/.../github-provider
```

GCP WIF の STS は audience を full URI 形式で検証する。
プレフィクスなしだと `invalid_grant: The audience in ID Token does not match` となる。
（PR #2 で修正済み。再発防止のためここに記録する。）

### `gcloud auth print-access-token` には Drive スコープの明示が必要

外部アカウント（WIF）ではデフォルトスコープが `cloud-platform` のみ。
Drive API へのアクセスには明示指定が必要。

```bash
gcloud auth print-access-token \
  --scopes=https://www.googleapis.com/auth/drive.readonly
```

gcloud が `--scopes` は external_account で "may be ignored" と警告するが、
実際には 403 → 成功 の変化が確認されており有効に機能している。

### `DRIVE_FOLDER_ID` はワークフローの `env:` ブロックで注入する

`scripts/drive-sync.sh` は起動時に `scripts/drive-sync.config.env` を source する。
bash の source は既存の環境変数を上書きするため、Secret を先に渡しても
config.env の代入で潰れてしまう。

対策として config.env 側を条件付き代入にし、env var を優先させる:

```bash
# scripts/drive-sync.config.env
DRIVE_FOLDER_ID="${DRIVE_FOLDER_ID:-PASTE_DRIVE_FOLDER_ID_HERE}"
```

ワークフロー側で Secret を env var として注入:

```yaml
# .github/workflows/drive-sync.yml
- run: bash scripts/drive-sync.sh
  env:
    DRIVE_FOLDER_ID: ${{ secrets.DRIVE_FOLDER_ID }}
```

---

## GCP 構成（固定）

| 項目 | 値 |
|------|----|
| Project | agent-lab-integrations |
| Project Number | 147807620986 |
| WIF Pool | github-pool |
| WIF Provider | github-provider |
| Service Account | drive-uploader@agent-lab-integrations.iam.gserviceaccount.com |
| Drive API | 有効化済み |

---

## セキュリティ特性

- サービスアカウントキー（JSON）: **不使用**
- 認証情報の有効期間: ID Token の TTL（最大 1 時間）のみ
- 権限範囲: Drive フォルダへの書き込みのみ（SA に付与）
- リポジトリに保存する Secret: フォルダ ID のみ（認証情報ゼロ）

---

## 代替案と却下理由

| 案 | 却下理由 |
|----|---------|
| SA キー JSON を Secret に保存 | 鍵漏洩リスク、ローテーション運用コスト |
| `google-github-actions/auth` Action | 依存 Action 追加を避けてスクリプトで完結させる方針 |
| OAuth2 ユーザー認証 | CI/CD に不向き、トークン管理が必要 |
