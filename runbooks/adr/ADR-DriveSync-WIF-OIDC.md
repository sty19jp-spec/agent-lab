# ADR: GitHub Actions → Google Drive 同期（WIF/OIDC・鍵レス）最終固定版

## 0. 目的
GitHub Actions から Google Drive へファイルをアップロードする同期を、Workload Identity Federation（OIDC）による鍵レス認証で実現し、設計・構成・現状を正本（Git）へ固定する。

## 1. 成功確認済みの完成状態
- Workflow: drive-sync.yml（feature/drive-sync）
- 認証方式: Workload Identity Federation（OIDC）
- Project: agent-lab-integrations
- Service Account: drive-uploader@agent-lab-integrations.iam.gserviceaccount.com
- WIF Pool: github-pool
- Provider: github-provider
- Drive API: 有効化済
- Repository Secrets:
  - GCP_WIF_PROVIDER
  - GCP_SERVICE_ACCOUNT
  - DRIVE_FOLDER_ID
- push → 自動実行 → Driveアップロード成功

## 2. アーキテクチャ（固定）
GitHub Actions → OIDC → WIF Provider → WIF Pool → Service Account → Drive API

## 3. セキュリティ設計
- credentials_json 不使用
- 鍵レス（OIDC）
- 権限はService Accountへ集約
