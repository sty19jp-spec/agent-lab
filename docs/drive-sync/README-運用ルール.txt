DriveSync 運用ルール

■ 正本
GitHub main が唯一の Source of Truth です。

■ 保存構造
- latest/ は常に最新1件だけ置きます。
- history/YYYY/YYYY-MM/ に月単位で履歴を残します。

■ 年次削除
- 1年以上経過した history/YYYY/ は手動で削除します。

■ 認証方式
- GitHub Actions → Google Drive は WIF / OIDC（鍵レス）で実行します。
