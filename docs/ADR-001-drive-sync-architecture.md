# ADR-001: Drive Sync アーキテクチャ設計決定記録

- **Date**: 2026-03-05
- **Status**: Accepted
- **Deciders**: sty19jp-spec
- **Confirmed Run**: 22709627994（`drive-sync.yml` 正常動作確認）

> **用語定義**
> - **ADR**: Architecture Decision Record — 設計上の重要な意思決定を記録する文書
> - **WIF**: GCP Workload Identity Federation — 外部 IdP のトークンを GCP access token に交換する仕組み
> - **OIDC**: OpenID Connect — GitHub Actions が発行する短命 ID Token の規格
> - **SA**: Service Account（GCP サービスアカウント）
> - **STS**: Security Token Service（GCP の token 交換エンドポイント）
> - **SA キー JSON**: サービスアカウントの秘密鍵ファイル。本設計では**不使用**

---

## 1. Context（背景）

GitHub Actions から Google Drive へファイルを自動同期する CI パイプラインが必要になった。
GCP リソースへのアクセスには認証が必要だが、従来の方式には以下の問題がある。

- **SA キー JSON を GitHub Secrets に保存する方式**は鍵漏洩リスクが高く、
  鍵の定期ローテーション運用コストも生じる。
- SA キーは一度漏洩すると有効期限まで悪用され続ける恐れがある。

一方、以下の技術的前提がある。

- GitHub Actions は **OIDC** により短命 ID Token を発行できる。
- GCP は **WIF** により外部 IdP（GitHub OIDC）のトークンを GCP access token に交換できる。

---

## 2. Decision（決定）

**GitHub Actions の OIDC と GCP Workload Identity Federation を組み合わせ、
SA キー JSON を一切使用しない鍵レス認証を採用する。**

実装方針:

1. GCP に WIF Pool / Provider を作成し、GitHub OIDC エンドポイントを外部 IdP として登録する。
2. `scripts/drive-sync.sh` が OIDC token を自前で取得し、`gcloud` コマンドで WIF token 交換を行う。
3. `google-github-actions/auth` 等の外部 Action は使用せず、スクリプト完結とする。

---

## 3. Consequences（結果と影響）

### Positive（メリット）

| 項目 | 内容 |
|------|------|
| 鍵レス | SA キー JSON が存在しないため鍵漏洩リスクがゼロ |
| 短命トークン | access token の有効期間は最大 1 時間。漏洩時の影響範囲が限定される |
| Secret 最小化 | GitHub Secret は `DRIVE_FOLDER_ID` のみ。認証情報を Secret に保存しない |
| ローテーション不要 | 鍵が存在しないため定期ローテーション運用が不要 |

### Negative / Trade-offs（デメリット・トレードオフ）

| 項目 | 内容 |
|------|------|
| GCP 初期設定 | WIF Pool / Provider の初回構築が必要（一度設定すれば変更不要） |
| gcloud 依存 | CI 環境に `gcloud` CLI が必要（`ubuntu-latest` には標準インストール済み） |
| ハマりポイントあり | OIDC audience の形式など、設定ミスで `invalid_grant` になりやすい（§ 5 参照） |

---

## 4. GitHub バックアップを Drive に採用した理由

| 観点 | 内容 |
|------|------|
| 正本 | GitHub `main` ブランチが唯一の Source of Truth |
| バックアップの位置付け | Google Drive は補助コピー。GitHub 外部でのファイル参照・共有・復旧に使用 |
| 自動化 | push 時に自動同期。人手での操作が不要 |
| 保持構造 | `latest/`（最新 1 件）と `history/YYYY-MM/`（月次アーカイブ 12 ヶ月保持）に分離 |

---

## 5. Authentication Flow（認証フロー詳細）

```
GitHub Actions Runner
  │
  ├─[1]─▶ GitHub OIDC エンドポイント (ACTIONS_ID_TOKEN_REQUEST_URL)
  │        audience=//iam.googleapis.com/<WIF_PROVIDER>
  │        ← ID Token (JWT, 短命) を受け取る
  │
  ├─[2]─▶ gcloud iam workload-identity-pools create-cred-config
  │        外部アカウント credential config JSON をローカルに生成
  │
  ├─[3]─▶ gcloud auth login --cred-file=<config.json>
  │        GCP STS が ID Token を検証
  │        SA impersonation で短命 access token を発行
  │        SA: drive-uploader@agent-lab-integrations.iam.gserviceaccount.com
  │
  └─[4]─▶ Drive API v3 呼び出し（Bearer access token）
           https://www.googleapis.com/drive/v3/files
```

---

## 6. Secret 管理方針

| 情報 | 保管場所 | 理由 |
|------|----------|------|
| `DRIVE_FOLDER_ID` | GitHub Secrets のみ | フォルダ ID は外部に公開しない |
| `GCP_WIF_PROVIDER` | `scripts/drive-sync.config.env`（リポジトリ内） | WIF Provider のリソース名は非機密情報 |
| `GCP_SERVICE_ACCOUNT` | `scripts/drive-sync.config.env`（リポジトリ内） | SA メールは非機密情報 |
| SA キー JSON | **保存しない** | 本設計の採用動機がここにある |

ワークフローは `env: DRIVE_FOLDER_ID: ${{ secrets.DRIVE_FOLDER_ID }}` で Secret を明示注入する。
`config.env` の条件付き代入 `${DRIVE_FOLDER_ID:-PASTE_DRIVE_FOLDER_ID_HERE}` により、
環境変数が存在する場合は `config.env` の値で上書きされない。

---

## 7. Security モデル

```
┌──────────────────────────────────────────────────────────┐
│ 権限境界                                                  │
│                                                           │
│  GitHub Actions runner                                    │
│    ├── 読み取り: リポジトリファイル（contents: read）     │
│    └── OIDC 発行: id-token: write のみ                   │
│                                                           │
│  GCP Service Account (drive-uploader)                    │
│    └── Google Drive API への書き込み権限のみ             │
│        （他の GCP リソースへのアクセス権なし）           │
│                                                           │
│  Token のライフサイクル                                   │
│    ├── OIDC ID Token: 1 実行につき 1 回発行。短命。      │
│    └── GCP access token: 最大 1 時間。ジョブ終了で破棄。 │
└──────────────────────────────────────────────────────────┘
```

- **最小権限原則**: SA は Drive への書き込みのみ。GCP プロジェクト全体の権限は持たない。
- **短命トークン**: SA キーのような永続的な認証情報をどこにも保存しない。
- **ゼロ永続鍵**: ローテーション不要。漏洩しても次の実行には影響しない。

---

## 8. 運用モデル

```
feature ブランチで開発
       │
       ▼
PR 作成 → CI チェック → レビュー
       │
       ▼ human merge（直 push 禁止推奨）
main ブランチ
       │
       ▼
drive-sync.yml 自動起動 → Drive バックアップ
```

- **feature → PR → CI → human merge** を標準フローとする。
- `main` への直 push は可能だが、重要な変更は PR 経由を推奨する。
- `workflow_dispatch` で任意のタイミングに手動実行可能。

---

## 9. 採用しなかった代替案

| 案 | 却下理由 |
|----|---------|
| SA キー JSON を GitHub Secret に保存 | 鍵漏洩リスク。定期ローテーション運用コスト |
| `google-github-actions/auth` Action を使用 | 外部 Action への依存を避け、スクリプト完結を優先 |
| OAuth2 ユーザー認証 | CI/CD に不向き。ユーザートークンの管理が必要 |
| Personal Access Token（PAT） | GCP への認証には使用不可 |

---

## 10. GCP 構成参照

| 項目 | 値 |
|------|----|
| Project ID | agent-lab-integrations |
| Project Number | 147807620986 |
| WIF Pool | github-pool |
| WIF Provider | github-provider |
| Service Account | drive-uploader@agent-lab-integrations.iam.gserviceaccount.com |
| Drive API | 有効化済み |
| WIF Provider リソース名 | `projects/147807620986/locations/global/workloadIdentityPools/github-pool/providers/github-provider` |

---

## 11. 既知のハマりポイント

### Pitfall 1: OIDC audience に `//iam.googleapis.com/` プレフィクスが必須

```bash
# NG: bare resource path → invalid_grant エラー
audience=${GCP_WIF_PROVIDER}
# → projects/147807620986/.../github-provider

# OK: full URI 形式
audience=//iam.googleapis.com/${GCP_WIF_PROVIDER}
# → //iam.googleapis.com/projects/147807620986/.../github-provider
```

GCP STS は audience を full URI 形式で検証する。プレフィクスなしだと
`invalid_grant: The audience in ID Token does not match` になる。

### Pitfall 2: external_account での `--scopes` フラグ警告

```
WARNING: `--scopes` flag may not work as expected and will be ignored
         for account type external_account.
```

WIF（external_account）では `gcloud auth print-access-token --scopes=...` の
`--scopes` が "ignored" と警告が出るが、Drive API 疎通は成功している（Run 22709627994 確認済み）。
Drive スコープは SA の IAM 側で制御されているため、実際の権限には影響しない。

### Pitfall 3: `DRIVE_FOLDER_ID` は workflow の `env:` ブロックで注入する

`drive-sync.sh` は `config.env` を `source` する。
通常の `source` は既存の環境変数を上書きするため、事前にエクスポートしても潰れる。

対策として `config.env` を条件付き代入にしている。

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
