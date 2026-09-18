import AgentPetCore
import AgentPetLibrary
import AgentPetSprites
import AppKit
import SwiftUI

struct PetInstallReviewSheet: View {
  @ObservedObject var model: PetLibraryViewModel
  let review: PetLibraryViewModel.Review
  @State private var previewStatus: TaskVisualStatus = .ready

  var body: some View {
    let inspection = review.inspection
    let license = PetLibraryErrorText.licenseLabel(inspection.licenseStatus)
    VStack(alignment: .leading, spacing: DesignTokens.spaceL) {
      Text("Review pet before installing")
        .font(.headline)
      HStack(alignment: .top, spacing: DesignTokens.spaceL) {
        PetPreviewView(package: review.staged.package, status: previewStatus)
          .frame(width: DesignTokens.settingsPreviewSize, height: DesignTokens.settingsPreviewSize)
        VStack(alignment: .leading, spacing: DesignTokens.spaceS) {
          Text(inspection.displayName).font(.title3.weight(.semibold))
          Text("\(inspection.manifestID) · sprite v\(inspection.spriteVersion)")
            .foregroundStyle(.secondary)
          Text("Source: \(inspection.source.kind) \(inspection.source.value)")
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(2)
          HStack {
            StatusChip(text: license.text, tone: license.tone)
            if let name = inspection.license.name { Text(name).font(.callout) }
          }
          if let attribution = inspection.license.attribution {
            Text("By \(attribution)").font(.callout).foregroundStyle(.secondary)
          }
          Picker("Preview state", selection: $previewStatus) {
            ForEach(
              [TaskVisualStatus.ready, .working, .inputNeeded, .finished, .failed], id: \.self
            ) {
              Text($0.label).tag($0)
            }
          }
          .frame(maxWidth: 240)
        }
      }
      ForEach(inspection.warnings, id: \.rawValue) { warning in
        Label(warningText(warning), systemImage: "exclamationmark.triangle")
          .font(.callout)
      }
      HStack {
        Button("Cancel") { model.cancelReview() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        if inspection.duplicateOf == nil {
          Button("Install") { Task { await model.installReviewedPackage(useNow: false) } }
            .disabled(model.isBusy)
        }
        PrimaryActionButton(
          inspection.duplicateOf == nil ? "Install and Use" : "Use Existing Copy",
          isEnabled: !model.isBusy
        ) {
          Task { await model.installReviewedPackage(useNow: true) }
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(DesignTokens.settingsPaneInset)
    .frame(width: 520)
  }

  private func warningText(_ warning: PetInspectionWarning) -> String {
    switch warning {
    case .licenseUnknown:
      "No license information was found. You can use this pet locally, but \(AgentPetProduct.name) does not grant any redistribution rights."
    case .duplicateAsset:
      "This exact pet is already installed as \(review.inspection.duplicateOf ?? ""). The existing copy will be reused."
    case .manifestIDInUse:
      "Another pet already uses the ID \(review.inspection.manifestID). This one will be stored as \(review.inspection.proposedRecordID)."
    }
  }
}

struct PetRecordInfoSheet: View {
  let record: PetLibraryRecord
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spaceM) {
      Text(record.displayName).font(.headline)
      Grid(
        alignment: .leading, horizontalSpacing: DesignTokens.spaceL,
        verticalSpacing: DesignTokens.spaceS
      ) {
        infoRow("Library ID", record.recordID)
        infoRow("Manifest ID", record.manifestID)
        infoRow("Sprite version", "v\(record.spriteVersion)")
        infoRow("Source", "\(record.source.kind): \(record.source.value)")
        infoRow("Installed", record.installedAt.formatted(date: .abbreviated, time: .shortened))
        infoRow("License status", PetLibraryErrorText.licenseLabel(record.licenseStatus).text)
        if let name = record.license.name { infoRow("License", name) }
        if let url = record.license.url { infoRow("License URL", url) }
        if let attribution = record.license.attribution { infoRow("Attribution", attribution) }
        if let notice = record.license.noticeFile { infoRow("Notice file", notice) }
        infoRow("Package fingerprint", String(record.packageFingerprint.prefix(16)) + "…")
      }
      if !record.description.isEmpty {
        Text(record.description).font(.callout).foregroundStyle(.secondary)
      }
      HStack {
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(DesignTokens.settingsPaneInset)
    .frame(width: 460)
  }

  private func infoRow(_ label: String, _ value: String) -> some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(value).textSelection(.enabled).lineLimit(3)
    }
  }
}

extension PetLibraryRecord: Identifiable {
  public var id: String { recordID }
}
