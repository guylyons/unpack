import SwiftUI

/// The big glass target. Shrinks into a slim bar once there's work in the list.
struct DropZone: View {
    var isTargeted: Bool
    var compact: Bool
    var choose: () -> Void

    @State private var floating = false

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 14) {
                    hero(size: 54)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isTargeted ? "Let go to unpack" : "Drop more archives")
                            .font(.headline)
                        Text(Self.formats)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    chooseButton
                }
                .padding(14)
            } else {
                VStack(spacing: 14) {
                    hero(size: 150)
                        .padding(.top, 8)
                    Text(isTargeted ? "Let go to unpack" : "Drop archives here")
                        .font(.title2.weight(.semibold))
                        .contentTransition(.opacity)
                    Text(Self.formats)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    chooseButton
                        .padding(.top, 4)
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect(cornerRadius: compact ? 22 : 34))
        .glassEffect(
            .regular.tint(isTargeted ? Color.accentColor.opacity(0.35) : nil).interactive(),
            in: .rect(cornerRadius: compact ? 22 : 34)
        )
        .scaleEffect(isTargeted ? 1.025 : 1)
        .onAppear { floating = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop zone. Drop archive files here to unpack them.")
    }

    private func hero(size: CGFloat) -> some View {
        Image("Hero")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isTargeted ? -6 : 0))
            .scaleEffect(isTargeted ? 1.12 : 1)
            .offset(y: isTargeted ? -6 : (floating && !compact ? -4 : 0))
            .shadow(color: .black.opacity(0.18), radius: isTargeted ? 16 : 8, y: isTargeted ? 10 : 5)
            .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: floating)
            .animation(.spring(duration: 0.4, bounce: 0.45), value: isTargeted)
            .accessibilityHidden(true)
    }

    private var chooseButton: some View {
        Button(compact ? "Choose…" : "Choose Files…", action: choose)
            .buttonStyle(.glass)
            .controlSize(compact ? .regular : .large)
    }

    static let formats = "ZIP · RAR · 7Z · TAR · ISO · DMG and 50+ more"
}
