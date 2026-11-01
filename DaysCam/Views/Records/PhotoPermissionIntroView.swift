import SwiftUI

/// Shown in place of the photo wall the first time a record is opened while
/// photo access was never asked (PRD 2.0 §7.1, D8 ⑤): explains what each
/// choice of the coming system prompt means in DaysCam, full access first.
/// Only "繼續" triggers the prompt; going back leaves without asking.
/// `PhotoWallView` supplies the top bar.
struct PhotoPermissionIntroView: View {
    /// One choice of the system prompt and what it means here.
    struct Option: Identifiable {
        /// The prompt's own wording, so the user can match it (§7.7 exception).
        let title: String
        let points: [String]
        let isRecommended: Bool

        var id: String { title }
    }

    static let options = [
        Option(title: "允許完整取用",
               points: ["每個紀錄在「照片」App 有一本同名相簿",
                        "在「照片」App 放進相簿的照片，會自動出現在紀錄並標出第幾天",
                        "拍的照片直接存進該相簿"],
               isRecommended: true),
        Option(title: "限制取用",
               points: ["只看得到你挑選的照片",
                        "不建相簿、不和「照片」App 同步",
                        "照片要在 DaysCam 裡用「加入照片」或拍照加入"],
               isRecommended: false),
        Option(title: "不允許",
               points: ["紀錄看不到任何照片",
                        "之後可隨時到「設定」開啟"],
               isRecommended: false)
    ]

    /// The prompt is up: "繼續" is disabled so it asks only once.
    var isRequesting = false
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 8) {
                        Text("讓紀錄和「照片」App 同步")
                            .font(.title3.bold())
                            .foregroundColor(CameraTheme.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text("接下來 iOS 會詢問照片權限。三個選項在 DaysCam 的差別：")
                            .font(.subheadline)
                            .foregroundColor(CameraTheme.inkSecondary)
                            .lineSpacing(2)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                    ForEach(Self.options) { option in
                        OptionCard(option: option)
                    }
                    Text("選了之後都能到「設定 › DaysCam › 照片」更改。照片本身不會被修改，匯出時另存新照片。")
                        .font(.footnote)
                        .foregroundColor(CameraTheme.inkTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .accessibilityIdentifier("permissionIntroFootnote")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .accessibilityIdentifier("permissionIntroScroll")

            // Stays put while the options scroll.
            Button(action: onContinue) {
                Text("繼續")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(CameraTheme.inkOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(CameraTheme.accent))
            }
            .buttonStyle(.plain)
            .disabled(isRequesting)
            .accessibilityIdentifier("permissionIntroContinue")
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photoPermissionIntro")
    }
}

/// One option card: title, the "建議" tag on full access, and its points.
private struct OptionCard: View {
    let option: PhotoPermissionIntroView.Option

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(option.title)
                    .font(.headline)
                    .foregroundColor(CameraTheme.ink)
                if option.isRecommended {
                    Text("建議")
                        .font(.caption.weight(.heavy))
                        .foregroundColor(CameraTheme.inkOnAccent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(CameraTheme.accent))
                }
            }
            .padding(.bottom, 2)
            ForEach(option.points, id: \.self) { point in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                    Text(point)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .foregroundColor(CameraTheme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(option.isRecommended ? CameraTheme.active : CameraTheme.ink.opacity(0.08),
                              lineWidth: option.isRecommended ? 2 : 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("permissionIntroOption")
    }
}

#Preview {
    PhotoPermissionIntroView {}.background(CameraTheme.background)
}
