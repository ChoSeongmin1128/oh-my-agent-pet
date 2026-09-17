import AppKit
import SwiftUI

public enum StatusChipTone: Equatable, Sendable {
  case neutral
  case positive
  case warning
  case negative
  case info
}

struct SettingsSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.settingsRowSpacing) {
      Text(title)
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      VStack(alignment: .leading, spacing: 0) {
        content
      }
      .padding(DesignTokens.spaceM)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: DesignTokens.settingsSectionCornerRadius, style: .continuous)
          .fill(
            Color(nsColor: .controlBackgroundColor).opacity(DesignTokens.settingsSurfaceOpacity))
      )
      .overlay(
        RoundedRectangle(cornerRadius: DesignTokens.settingsSectionCornerRadius, style: .continuous)
          .strokeBorder(Color(nsColor: .separatorColor), lineWidth: DesignTokens.strokeSubtle)
      )
    }
  }
}

struct SettingsRow<Control: View>: View {
  let title: String
  let description: String?
  @ViewBuilder let control: Control

  init(_ title: String, description: String? = nil, @ViewBuilder control: () -> Control) {
    self.title = title
    self.description = description
    self.control = control()
  }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: DesignTokens.spaceL) {
        labels
        Spacer(minLength: DesignTokens.spaceM)
        control
      }
      VStack(alignment: .leading, spacing: DesignTokens.spaceS) {
        labels
        control
      }
    }
    .frame(minHeight: DesignTokens.settingsRowMinimumHeight)
    .padding(.vertical, DesignTokens.spaceS)
  }

  private var labels: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spaceXS) {
      Text(title)
      if let description {
        Text(description)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

struct StatusChip: View {
  let text: String
  let tone: StatusChipTone

  var body: some View {
    Text(text)
      .font(.caption.weight(.medium))
      .padding(.horizontal, DesignTokens.spaceS)
      .padding(.vertical, DesignTokens.spaceXS)
      .background(
        RoundedRectangle(cornerRadius: DesignTokens.settingsChipCornerRadius, style: .continuous)
          .fill(color.opacity(0.18))
      )
      .foregroundStyle(color)
      .accessibilityLabel(text)
  }

  private var color: Color {
    switch tone {
    case .neutral: Color(nsColor: DesignTokens.statusUnknown)
    case .positive: Color(nsColor: DesignTokens.statusCompleted)
    case .warning: Color(nsColor: DesignTokens.statusWaiting)
    case .negative: Color(nsColor: DesignTokens.statusFailed)
    case .info: Color(nsColor: DesignTokens.statusWorking)
    }
  }
}

struct PrimaryActionButton: View {
  let title: String
  let isEnabled: Bool
  let action: () -> Void

  init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
    self.title = title
    self.isEnabled = isEnabled
    self.action = action
  }

  var body: some View {
    Button(title, action: action)
      .buttonStyle(.borderedProminent)
      .controlSize(.regular)
      .disabled(!isEnabled)
  }
}
