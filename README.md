# Boticon

iPhone向けの壁紙選択・切り替えアプリのソースコードです。SwiftUIとApp Intentsを使用し、選択した画像を「ショートカット」へ渡します。

**元絵、生成画像、VTuberの名簿・プロフィール・ID、制作履歴、画像入りスクリーンショットは含めていません。** アプリは空の状態で起動し、配布元のHTTPS URLから壁紙パックを取り込みます。アプリの再ビルドは不要です。

## 機能

- URLからZIP＋JSONの壁紙パックを検証して追加・更新・削除。追加前に作成者・利用条件を表示。

- 所属別の絞り込み、名前検索、デビューの新旧・名前順、選択中のみ表示。
- 選択した画像の順次・ランダム取得と、直前の画像の連続選択回避。
- 画面のネイティブ寸法に合わせた壁紙出力。人物の画素サイズを変えず、指定した下隅を固定して背景を調整。
- App Intentによる画像の受け渡し、ショートカットの成功・キャンセル・エラー応答、削除・改名時の再設定案内。
- 写真シャッフル用の写真保存。通常のショートカット連携では、写真・ファイルへの保存は不要。
- Dynamic Type対応。アクセシビリティ文字サイズでは一覧を1列に表示。

## ビルド

macOS、Swift 6に対応したXcode、XcodeGenを用意します。アプリの最低対応OSはiOS 17です。

```sh
git clone https://github.com/rioriost/boticon.git
cd boticon
xcodegen generate
open BoticonWallpaper.xcodeproj
```

シミュレータでは署名なしでビルドできます。

```sh
xcodebuild -project BoticonWallpaper.xcodeproj -scheme BoticonWallpaper \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

実機ではXcodeのSigning & Capabilitiesでご自身のTeamを指定してください。既定のBundle Identifierは`com.example.boticon`、応答用URLスキームは`boticon`です。識別子を変更する場合は、`project.yml`、ショートカットのJSON・生成ツール、UIテストの識別子も合わせて変更します。応答スキームの変更時は`WallpaperShortcut.swift`とそのテストも更新してください。

## 壁紙パックを使う・配布する

アプリの「壁紙」画面左上の＋ → 配布元のHTTPS URLを入力 → 「パックを確認」 → 利用条件を確認 → 「このパックを追加」でカタログに追加します。配布元が別経路で示すSHA-256があれば入力して照合できます。追加した壁紙は所属・名前で検索し、選択してショートカットに渡せます。パック単位で削除でき、新版は同じ配布元・同じID・大きいrevisionで取り込みます。

[BWP v1の公開仕様](docs/wallpaper-pack-v1.md)と[JSON Schema](docs/wallpaper-pack-v1.schema.json)を公開しています。標準ZIPのstored形式（無圧縮）とUTF-8 JSONを使用します。PNG/JPEG、画像ごとのSHA-256・バイト数・画素数、出典、生成AI使用の有無をマニフェストへ記載します。容量制限、不正パス・リンク・実行ファイルの拒否、検証後の一括追加に対応しています。チェックサムは破損を検出しますが、配布元の身元や画像の権利を保証しません。

パック作成はPython標準ライブラリだけで実行できます。利用許諾を確認した画像とレシピを、公開ソースとは別に用意してください。

```sh
python3 tools/build_wallpaper_pack.py recipe.json input output.bwp.zip
```

入力レシピとディレクトリ構成は仕様書を参照してください。既存の出力は上書きしません。生成したアーカイブや実データはこのソースリポジトリへコミットしないでください。アプリには壁紙・名簿を一切組み込まず、空の`catalog.json`は従来の公開検査用に保持しています。

## 壁紙変更と自動切り替え

署名済みの`.shortcut`は含めません。次のどちらかで設定します。

- iPhoneの「ショートカット」で「次のBoticon壁紙を取得」→「壁紙に写真を設定」を作成し、アプリから返した画像を入力へ指定する。ショートカット名をアプリの連携設定へ入力する。
- 同梱のJSONから、ご自身のMacでテンプレートを生成・署名してアプリへ組み込む。

```sh
# 未署名のワークフローをbuild/へ生成するだけ
python3 tools/build_shortcut.py

# Appleの標準署名サービスを使い、ローカルのアプリ用リソースを作成
python3 tools/build_shortcut.py --sign
xcodegen generate
```

署名にはMac側のショートカット・Apple Account環境が必要です。`--sign`は画像や名簿を送らず、ワークフローをAppleのサービスへ送ります。失敗した場合は署名済みリソースを置換しません。未署名ファイルを、取り込み可能な署名済みファイルとは扱いません。

壁紙変更はiOSのショートカットが行います。初回の追加・許可、対象の壁紙の指定、時刻オートメーションの作成はiPhone側で必要です。アプリで頻度を選ぶだけでは自動実行されません。毎日・毎週などの時刻オートメーションから、作成したショートカットを実行してください。

アプリはショートカットの一覧や壁紙の最終表示を読み取れません。成功応答は実行の完了を示すもので、実際の表示は壁紙で確認します。シミュレータでは成功応答後もホーム画面が黒くなる事例があり、壁紙・ロック中・時刻実行の確認には実機を使用してください。

## テストと公開内容の検査

```sh
swift test
python3 -m unittest discover -s Tests -p 'test_*.py' -v

# 公開予定の変更をステージした後に実行
python3 tools/check_public_source.py
```

Swiftでは不正ZIP・チェックサム・画像制限・パック更新と保存・通信応答・選択・並び替え・壁紙の配置・URL応答を、Pythonではパック作成とショートカットを検証します。空の公開版の起動と説明画面は、`PublicSourceUITests`で確認します。

```sh
xcodebuild -project BoticonWallpaper.xcodeproj -scheme BoticonWallpaper \
  -destination 'id=<シミュレータのUDID>' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO \
  -only-testing:BoticonWallpaperUITests/PublicSourceUITests test
```

公開検査はGitのステージ内容と追跡ファイルを確認し、許可リスト外の画像・署名ファイル・制作データ・認証情報・空でないカタログを拒否します。元の制作環境の履歴を継承せず、新しい履歴から公開しています。

## プライバシー

本アプリは個人情報を収集しません。画像・設定の端末内での扱い、任意の写真保存、ショートカット連携については[プライバシーポリシー](PRIVACY.md)をご覧ください。

公開URL：<https://github.com/rioriost/boticon/blob/main/PRIVACY.md>

## ライセンスと素材の権利

コードと文書は[MIT License](LICENSE)です。別途用意した画像、キャラクター、名称、ロゴ、データセットなどの権利を許諾するものではありません。

生成AIによる画像を使用する場合も、参照元や権利者の条件を個別に確認し、非公式・生成AI使用の表示など、必要な案内をご自身の配布物へ追加してください。このソフトウェアは権利者の公式・公認アプリであることを示しません。
