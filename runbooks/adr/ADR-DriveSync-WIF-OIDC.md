# ADR: GitHub Actions から Google Drive への同期に WIF / OIDC 鍵レス認証を採用する

- **Date**: 2026-03-05
- **Status**: Accepted
- **Deciders**: sty19jp-spec
- **Confirmed run**: 22701686259

---

## Context

GitHub Actions から Google Drive へファイルを自動同期する機能が必要になった。
GCP リソースへのアクセスには認証情報が必要だが、以下の問題がある。

- サービスアカウントキー（JSON）をリポジトリ Secret に保存する方式は、
  鍵の漏洩リスクが高く、定期ローテーションの運用コストが生じる。
- GitHub Actions には OIDC（OpenID Connect）による短命トークン発行機能がある。
- GCP には Workload Identity Federation（WIF）があり、外部 IdP の OIDC トークンを
  GCP の access token へ交換できる。

---

## Decision

**GitHub Actions の OIDC と GCP Workload Identity Federation を組み合わせ、
サービスアカウントキーを一切使用しない鍵レス認証を採用する。**

実装方針:
- 外部 IdP として GitHub OIDC エンドポイントを WIF Provider に登録する。
- `scripts/drive-sync.sh` が OIDC token を取得し、`gcloud` コマンドで token 交換を行う。
- `google-github-actions/auth` 等の外部 Action は使用せず、スクリプトで完結させる。

---

## Consequences

### Positive

- サービスアカウントキーが存在しないため、鍵漏洩リスクがゼロ。
- トークンの有効期間が短命（最大 1 時間）であり、漏洩時の影響範囲が限定される。
- リポジトリに保存する Secret はフォルダ ID のみ（認証情報ゼロ）。
- キーローテーション運用が不要。

### Negative / Trade-offs

- GCP 側の WIF Pool / Provider 設定が必要（初期構築コストあり）。
- `gcloud` コマンドが CI 環境に必要（ubuntu-latest には標準インストール済み）。
- OIDC audience の形式（後述）や Drive スコープの扱いにハマりポイントがある。

---

## Appendix A: Authentication Flow

```
GitHub Actions Runner
  |
  +-1-> GitHub OIDC エンドポイント（ACTIONS_ID_TOKEN_REQUEST_URL）
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

## Appendix B: Implementation Pitfalls

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

`scripts/drive-sync.sh` は `scripts/drive-sync.config.env` を source する。
bash の source は既存の環境変数を上書きするため、Secret を先に渡しても潰れてしまう。

対策: config.env 側を条件付き代入にし、env var を優先させる。

```bash
# scripts/drive-sync.config.env
DRIVE_FOLDER_ID="${DRIVE_FOLDER_ID:-PASTE_DRIVE_FOLDER_ID_HERE}"
```

```yaml
# .github/workflows/drive-sync.yml
- run: bash scripts/drive-sync.sh
  env:
    DRIVE_FOLDER_ID: ${{ secrets.DRIVE_FOLDER_ID }}
```

---

## Appendix C: GCP Configuration

| 項目 | 値 |
|------|----|
| Project | agent-lab-integrations |
| Project Number | 147807620986 |
| WIF Pool | github-pool |
| WIF Provider | github-provider |
| Service Account | drive-uploader@agent-lab-integrations.iam.gserviceaccount.com |
| Drive API | 有効化済み |

---

## Appendix D: Alternatives Considered

| 案 | 却下理由 |
|----|---------|
| SA キー JSON を Secret に保存 | 鍵漏洩リスク、ローテーション運用コスト |
| `google-github-actions/auth` Action | 依存 Action 追加を避けてスクリプトで完結させる方針 |
| OAuth2 ユーザー認証 | CI/CD に不向き、トークン管理が必要 |
