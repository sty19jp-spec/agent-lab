# ADR: Drive Sync に OAuth refresh_token フローを採用する

- **Date**: 2026-03-06
- **Status**: Accepted
- **Supersedes**: ADR-DriveSync-WIF-OIDC.md
- **Deciders**: sty19jp-spec
- **Confirmed run**: 22738463895

---

## Context

WIF/OIDC による鍵レス認証（ADR-DriveSync-WIF-OIDC.md）を実装したが、以下の問題が発生した。

- `gcloud auth print-access-token` で取得した access token では Drive API の multipart upload が動作しなかった。
- WIF 外部アカウントの Drive スコープ扱いが不安定で、403 エラーが継続した。
- OAuth クライアントが属する GCP プロジェクト（`agent-lab-integrations-489319`、project number: `266557062033`）と、Drive API を有効化したプロジェクトが一致しない状態が続いた。

これらの問題を解消するため、OAuth refresh_token フローへの切り替えを決定した。

---

## Decision

**GitHub Secrets に保管した OAuth refresh_token を用いて access_token を取得し、Drive API v3 の multipart upload でファイルをアップロードする。**

実装方針:
- `scripts/drive-sync.sh` が直接 `oauth2.googleapis.com/token` を呼び出して access_token を取得する。
- Drive API へのアップロードは `multipart/related` 形式で行う。multipart ボディの構築は Python で行い、CRLF や binary の扱いを確実にする。
- WIF/OIDC・gcloud コマンドへの依存を完全に排除する。

---

## Architecture

```
GitHub Actions
  |
  | secrets: DRIVE_OAUTH_CLIENT_ID / CLIENT_SECRET / REFRESH_TOKEN
  v
POST https://oauth2.googleapis.com/token
  grant_type=refresh_token
  |
  | access_token (short-lived, ~1h)
  v
POST https://www.googleapis.com/upload/drive/v3/files
  ?uploadType=multipart
  Content-Type: multipart/related; boundary=...
  |
  | HTTP 200 + file id
  v
Google Drive
  ├── latest/backup-latest.tar.gz
  └── history/YYYY-MM/backup-YYYY-MM.tar.gz
```

---

## Secrets

| Secret 名 | 用途 |
|-----------|------|
| `DRIVE_OAUTH_CLIENT_ID` | OAuth クライアント ID |
| `DRIVE_OAUTH_CLIENT_SECRET` | OAuth クライアントシークレット |
| `DRIVE_OAUTH_REFRESH_TOKEN` | リフレッシュトークン（長期・GitHub Secrets に保管） |
| `DRIVE_FOLDER_ID` | Drive アップロード先フォルダ ID |

OAuth クライアントは GCP プロジェクト `agent-lab-integrations-489319`（project number: `266557062033`）に属する。Drive API はこのプロジェクトで有効化済み。

---

## Consequences

### Positive

- WIF/OIDC・gcloud コマンドの依存がなく、実装がシンプル。
- `multipart/related` アップロードが安定して動作する（Python でボディを構築）。
- GCP IAM / WIF Pool / Provider の設定が不要。
- Drive API が有効なプロジェクトと OAuth クライアントのプロジェクトを一致させれば動作する。

### Negative / Trade-offs

- refresh_token は長命（失効しない限り有効）であり、漏洩時のリスクが WIF より高い。
- トークンを GitHub Secrets に保管するため、定期的な確認・再発行の運用が必要。
- refresh_token が失効した場合（Google アカウントのパスワード変更等）は手動で再取得が必要。

---

## Appendix A: Implementation Notes

### multipart ボディの構築は Python で行う

bash の `printf` による CRLF 生成はバイナリファイルと組み合わせると不安定なため、Python で構築する。

```python
with open(output_path, 'wb') as out:
    out.write(('--' + boundary + '\r\n').encode())
    out.write(b'Content-Type: application/json; charset=UTF-8\r\n\r\n')
    out.write(metadata.encode('utf-8'))
    out.write(b'\r\n')
    out.write(('--' + boundary + '\r\n').encode())
    out.write(b'Content-Type: application/gzip\r\n\r\n')
    out.write(file_data)
    out.write(b'\r\n')
    out.write(('--' + boundary + '--\r\n').encode())
```

### command substitution 内の log 出力は stderr へリダイレクトする

`drive_find_or_create_folder` / `drive_upload_file` は command substitution `$(...)` で呼ばれる。
内部の `log` 呼び出しが stdout に書くと、フォルダ ID や file ID にログ文字列が混入して
Drive API へ不正な parent ID を渡し HTTP 400 が発生する。

```bash
log "  Creating folder '${name}'..." >&2  # stdout ではなく stderr へ
```

---

## Appendix B: Alternatives Considered

| 案 | 状態 | 理由 |
|----|------|------|
| WIF/OIDC + gcloud | Superseded | Drive API multipart upload が動作しなかった |
| SA キー JSON を Secret に保存 | 却下 | 鍵漏洩リスク、ローテーション運用コスト |
| `google-github-actions/auth` Action | 却下 | 外部 Action 依存を避ける方針 |
| resumable upload | 未採用 | 小ファイル（< 5MB）のため multipart で十分 |
