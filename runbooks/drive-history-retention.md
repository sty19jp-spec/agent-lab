# Drive History 保持・削除ポリシー

ステータス: **自動化実装済み（週次 dry-run / 手動 delete）**

---

## 保持ポリシー

| パス | 役割 | 保持期間 |
|------|------|----------|
| `latest/` | 最新 1 件のみ | 常に上書き（保持期間なし） |
| `history/YYYY-MM/` | 月単位アーカイブ | **12 ヶ月**（経過後削除対象） |

削除単位は `history/YYYY-MM/` フォルダ単位（月次）。

---

## 仕組み：dry-run → confirm+delete の 2 段階

```
[Stage 1] dry-run（自動 / デフォルト）
  - 削除対象の YYYY-MM フォルダ名と Drive ID をログ出力するだけ
  - 何も削除しない
  - schedule（週次）は常にこのモードで動く

[Stage 2] confirm + delete（手動のみ）
  - workflow_dispatch で confirm_delete=yes を明示入力した場合のみ実行
  - デフォルトはゴミ箱移動（30 日後に自動消去）
  - hard_delete=yes を追加した場合のみ即時完全削除
```

---

## 自動実行（schedule）

`.github/workflows/drive-retention.yml` が毎週日曜 02:00 UTC に起動し、
**dry-run のみ** 実行する。ログで削除候補を確認できるが、実際の削除は行わない。

---

## 手動実行：workflow_dispatch

GitHub Actions の `Drive History Retention` ワークフローを手動実行する。

### パラメータ

| パラメータ | 説明 | 値 |
|-----------|------|----|
| `retain_months` | 保持月数（デフォルト 12） | 整数（例: `6`） |
| `confirm_delete` | 削除を実行する場合のみ `yes` と入力 | `yes` / 空欄 |
| `hard_delete` | ゴミ箱を経由せず即時完全削除する場合のみ `yes` | `yes` / 空欄 |

### 手順 A：dry-run（対象確認だけ）

```
1. Actions → Drive History Retention → Run workflow
2. retain_months: 12（または任意の月数）
3. confirm_delete: （空欄のまま）
4. hard_delete: （空欄のまま）
5. Run workflow
→ ログに削除候補フォルダ名と ID が出力される。削除はしない。
```

### 手順 B：ゴミ箱移動（通常削除）

```
1. 手順 A で dry-run を実行し、対象フォルダをログで必ず確認する
2. Actions → Drive History Retention → Run workflow
3. retain_months: 12
4. confirm_delete: yes
5. hard_delete: （空欄のまま）
6. Run workflow
→ 対象フォルダが Drive ゴミ箱に移動される（30 日後に自動消去）
```

### 手順 C：即時完全削除（hard delete）

```
1. 手順 A で dry-run を実行し、対象フォルダをログで必ず確認する
2. Actions → Drive History Retention → Run workflow
3. retain_months: 12
4. confirm_delete: yes
5. hard_delete: yes
6. Run workflow
→ 対象フォルダが即時完全削除される（復元不可）
```

---

## 誤削除防止

### YYYY-MM 以外は対象外

`drive-history-clean.sh` は `history/` 直下のフォルダ名を正規表現
`^[0-9]{4}-[0-9]{2}$` で検証する。一致しないフォルダは必ずスキップし、
ログに `WARN Skipping non-YYYY-MM folder` を出力する。

### ログで対象月と ID を確認できる

削除実行前に必ず以下のログが出力される：

```
---- Deletion candidates (older than YYYY-MM) ----
  2024-01  (id: 1AbCdEfGhIjKlMnOpQrStUvWx)
  2024-02  (id: 2BcDeFgHiJkLmNoPqRsTuVwXy)
----------------------------------------------------
```

dry-run モードではこの一覧が出力された後 `DRY-RUN mode. No changes made.` で終了する。

### schedule は dry-run のみ

`drive-retention.yml` の `schedule` トリガーは引数なしで
`drive-history-clean.sh` を呼び出すため、常に dry-run になる。
`--confirm --delete` はスクリプトに渡されない。

---

## スクリプト直接実行（CLI / 緊急時）

```bash
# dry-run（デフォルト）
bash scripts/drive-history-clean.sh

# 保持期間を 6 ヶ月に変更して dry-run
bash scripts/drive-history-clean.sh --retain-months 6

# ゴミ箱移動
bash scripts/drive-history-clean.sh --retain-months 12 --confirm --delete

# 即時完全削除
bash scripts/drive-history-clean.sh --retain-months 12 --confirm --delete --hard-delete
```

事前に以下の環境変数が必要（CI 外で実行する場合は手動でエクスポート）：

```bash
export GCP_WIF_PROVIDER=projects/.../providers/github-provider
export GCP_SERVICE_ACCOUNT=drive-uploader@....iam.gserviceaccount.com
export DRIVE_FOLDER_ID=<Drive フォルダ ID>
export ACTIONS_ID_TOKEN_REQUEST_URL=<OIDC URL>
export ACTIONS_ID_TOKEN_REQUEST_TOKEN=<OIDC Token>
```

---

## 関連ファイル

| ファイル | 役割 |
|---------|------|
| `scripts/drive-history-clean.sh` | 削除スクリプト本体 |
| `.github/workflows/drive-retention.yml` | 週次 dry-run + 手動削除ワークフロー |
| `docs/drive-sync/drive-folder-structure.md` | フォルダ構造定義 |
| `runbooks/drive-sync.md` | 同期運用 Runbook |
