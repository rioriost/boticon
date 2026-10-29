import SwiftUI

struct AboutView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("壁紙パックを追加して使います") {
                    Text("このアプリには壁紙やVTuberの名簿を同梱していません。利用する壁紙は、配布元のURLからパックを取得して追加します。パックの作成者・利用条件・画像ごとの出典と生成AIの使用表示は、配布者が記載した情報です。")
                        .accessibilityIdentifier("sourceOnlyDisclosure")
                    Link("ソースコードとMITライセンス", destination: URL(string: "https://github.com/rioriost/boticon")!)
                }
                Section("プライバシー") {
                    Text("本アプリは個人情報を収集しません。画像と設定は端末内で扱います。パック取得時は、指定した配布先にIPアドレスなどの通信情報が伝わります。")
                    Link("プライバシーポリシー", destination: URL(string: "https://github.com/rioriost/boticon/blob/main/PRIVACY.md")!)
                        .accessibilityIdentifier("privacyPolicyLink")
                }
                Section("画像と生成AIについて") {
                    Text("生成AIで制作した画像を追加する場合は、生成AIを使った非公式の画像であることを、利用者が分かる形で明示してください。元のデザインと異なる部分が含まれる場合があります。")
                }
                Section("公式アプリ・公式画像ではありません") {
                    Text("このソフトウェアは、キャラクターや画像の権利者が提供・公認・監修するアプリであることを示しません。公式作品と誤認される表示は避けてください。")
                    Text("画像、キャラクター、名称、ロゴ、参照素材、データセットなどの権利は、それぞれの権利者に帰属します。ソースコードのMITライセンスは、別途用意した素材の利用許諾を意味しません。")
                }
                Section("素材を利用・配布する前に") {
                    Text("ご自身で追加する素材は、参照元・権利者の最新の利用条件を確認してください。アプリで表示や保存ができても、画像の再配布・販売・商用利用への包括的な許諾があることにはなりません。必要な許諾と、非公式・生成AI利用などの案内を、ご自身の配布物へ用意してください。")
                }
            }
            .navigationTitle("このアプリについて")
        }
    }
}
