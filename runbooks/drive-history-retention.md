# Drive History 保持・削除ポリシー（スタブ）

ステータス: **設計方針確定 / 手動運用中 / 自動化未実装**

---

## 保持方針

| パス | 役割 | 保持期間 |
|------|------|----------|
| `latest/` | 最新 1 件のみ | 常に上書き（保持期間なし） |
| `history/YYYY/YYYY-MM/` | 月単位アーカイブ | **1 年**（経過後削除対象） |

削除単位: `history/YYYY/` ディレクトリ単位（年次一括）。

---

## 削除条件

- 対象年の 12 月末日から 1 年以上経過していること
- 例: `history/2025/` は 2026-12-31 以降が削除可

---

## 手動削除手順（現行）

```bash
# 1. 対象フォルダを Drive で確認
#    Google Drive UI -> agent-lab/drive-sync/history/<YYYY>/

# 2. Drive UI でフォルダを右クリック -> ゴミ箱に移動

# 3. 30 日後にゴミ箱から自動削除（または即時: ゴミ箱を空にする）
```

Drive API で削除する場合（要 drive スコープ）:
```bash
# フォルダ ID を確認してから実行
FOLDER_ID="<history/YYYY/ のフォルダ ID>"
ACCESS_TOKEN="$(gcloud auth print-access-token --scopes=https://www.googleapis.com/auth/drive)"
curl -X DELETE \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "https://www.googleapis.com/drive/v3/files/${FOLDER_ID}"
```

---

## 将来の自動化（拡張点）

- [ ] `drive-sync.sh` に年次削除ステップを追加
  - 実行タイミング: 毎年 1 月の `schedule` トリガー or `workflow_dispatch`
  - 削除前に dry-run モード（`DRIVE_DELETE_DRY_RUN=true`）で対象をログ出力
- [ ] 削除前に `history/<YYYY>/` の存在確認と件数チェック
- [ ] 削除結果を GitHub Issues または Slack へ通知（監査ログ代替）

---

## 関連ファイル

- `docs/drive-sync/drive-folder-structure.md` — フォルダ構造定義
- `docs/drive-sync/README-運用ルール.txt` — 運用ルール原文
- `runbooks/drive-sync.md` — 同期運用 Runbook
