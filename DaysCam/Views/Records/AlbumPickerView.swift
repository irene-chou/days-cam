import SwiftUI

/// Picks the album a record is bound to (PRD 2.0 FR-21.4): "建立新相簿" first,
/// then the user's albums with their photo counts. No thumbnails.
struct AlbumPickerView: View {
    @StateObject var model: AlbumPickerModel

    init(model: AlbumPickerModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        List {
            ForEach(model.options) { option in
                Button {
                    model.select(albumIdentifier: option.id)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .font(.system(size: 17))
                                .foregroundColor(CameraTheme.ink)
                                .lineLimit(1)
                            if let detail = option.detail {
                                Text(detail)
                                    .font(.system(size: 13).monospacedDigit())
                                    .foregroundColor(CameraTheme.inkTertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if option.isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(CameraTheme.active)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([option.title, option.detail].compactMap { $0 }.joined(separator: "，"))
                .accessibilityAddTraits(option.isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("albumOption")
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(CameraTheme.background.ignoresSafeArea())
        .navigationTitle("相簿")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("albumPicker")
        .task { await model.load() }
        .alert("無法完成", isPresented: errorBinding) {
            Button("好") { model.lastError = nil }
        } message: {
            if let error = model.lastError as? ProfileStoreError {
                Text(error.displayMessage)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })
    }
}
