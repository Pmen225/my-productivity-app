import SwiftUI

/// Version, build, and the privacy statement users are entitled to see.
struct AboutSettingsSection: View {
    @Environment(\.colorScheme) private var scheme

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        FlowCard {
            VStack(alignment: .leading, spacing: FlowSpacing.m) {
                FlowEyebrow("About")

                Text("Flowmap \(version) (\(build))")
                    .font(FlowFont.secondary)
                    .foregroundStyle(FlowTheme.primaryText(scheme))

                Text(
                    "Your data stays in your private iCloud database. Nothing leaves your devices except the content you explicitly send to your chosen AI provider when using the Assistant."
                )
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
