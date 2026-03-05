# Drive History 保持・削除ポリシー

ステータス: **設計方針確定 / 手動運用中 / 自動化未実装**

---

## 年次削除方針

| パス | 役割 | 保持期間 |
|------|------|----------|
| `latest/` | 最新 1 件のみ | 常に上書き（保持期間なし） |
| `history/YYYY/YYYY-MM/` | 月単位アーカイブ | **1 年**（経過後削除対象） |

**削除単位**: `history/YYYY/` ディレクトリ単位（年次一括）。

**削除条件**: 対象年の 12 月末日から 1 年以上経過していること。

| フォルダ | 削除可能日 |
|---------|-----------|
| `history/2025/` | 2026-12-31 以降 |
| `history/2026/` | 2027-12-31 以降 |

---

## 想定フォルダ構造

```
Google Drive
└── agent-lab
    └── drive-sync
        ├── latest/
        │   └── backup-latest.txt       <- push のたびに上書き
        ├── history/
        │   ├── 2025/
        │   │   ├── 2025-01/
        │   │   │   └── backup-2025-01.txt
        │   │   ├── 2025-02/
        │   │   │   └── backup-2025-02.txt
        │   │   └── ...
        │   └── 2026/
        │       ├── 2026-01/
        │       │   └── backup-2026-01.txt
        │       └── ...                  <- 当年分は保持
        └── README-運用ルール.txt
```

`history/YYYY/` 単位で削除する。月単位（`YYYY-MM/`）での削除は行わない。

---

## 手動削除手順

### Drive UI で削除（推奨）

```
1. Google Drive を開く
2. agent-lab/drive-sync/history/ へ移動
3. 削除対象の YYYY/ フォルダを右クリック → ゴミ箱に移動
4. ゴミ箱を空にする（即時削除）または 30 日後に自動削除
```

### Drive API で削除（CLI）

```bash
# 1. WIF 認証して access token を取得
#    （drive-sync.sh の認証フローに準じる）
ACCESS_TOKEN="$(gcloud auth print-access-token --scopes=https://www.googleapis.com/auth/drive)"

# 2. 削除対象フォルダの ID を確認
PARENT_FOLDER_ID="<drive-sync フォルダの ID>"
curl -fsSL \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "https://www.googleapis.com/drive/v3/files?q='${PARENT_FOLDER_ID}'+in+parents&fields=files(id,name)" \
  | jq '.files[] | select(.name | startswith("20"))'

# 3. 対象フォルダ ID を確認してから削除（ゴミ箱へ移動）
TARGET_FOLDER_ID="<history/YYYY/ のフォルダ ID>"
curl -X DELETE \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "https://www.googleapis.com/drive/v3/files/${TARGET_FOLDER_ID}"
```

**注意**: `DELETE` はゴミ箱へ移動する（即時削除ではない）。
即時削除する場合は `?supportsAllDrives=true` や別エンドポイントを使用する。

---

## 将来の自動化（拡張点）

- [ ] `drive-sync.yml` に年次削除ジョブを追加
  - 実行タイミング: 毎年 1 月の `schedule` トリガー or `workflow_dispatch`
  - 削除前に dry-run モード（`DRIVE_DELETE_DRY_RUN=true`）で対象をログ出力
- [ ] 削除前に `history/<YYYY>/` の存在確認と件数チェック
- [ ] 削除結果を GitHub Issues または Slack へ通知（監査ログ代替）

---

## 関連ファイル

- `docs/drive-sync/drive-folder-structure.md` — フォルダ構造定義
- `docs/drive-sync/README-運用ルール.txt` — 運用ルール原文
- `runbooks/drive-sync.md` — 同期運用 Runbook
