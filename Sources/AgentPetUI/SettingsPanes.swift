import AgentPetLibrary
import AgentPetSprites
import AppKit
import SwiftUI

struct SettingsRootView: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.settingsSectionSpacing) {
        switch model.pane {
        case .general:
          GeneralSettingsPane(model: model)
        case .pet:
          PetSettingsPane(model: model.petLibrary)
        case .card:
          CardSettingsPane(model: model)
        case .connections, .privacyDiagnostics:
          GeneralSettingsPane(model: model)
        }
      }
      .padding(DesignTokens.settingsPaneInset)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(
      minWidth: DesignTokens.settingsWindowSize.width,
      minHeight: DesignTokens.settingsWindowSize.height
    )
  }
}

struct GeneralSettingsPane: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    SettingsSection("Display") {
      SettingsRow(
        "Show pet and cards",
        description: "Hides the desktop pet and its cards. The menu bar keeps collecting status."
      ) {
        Toggle(
          "",
          isOn: Binding(
            get: { model.overlayState.isVisible },
            set: { _ in model.perform(.toggleVisibility) }
          )
        )
        .labelsHidden()
        .toggleStyle(.switch)
      }
      Divider()
      SettingsRow("Pet position", description: "Moves the pet back to the default corner.") {
        Button("Reset Position") { model.perform(.resetPosition) }
      }
    }
  }
}

struct CardSettingsPane: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    SettingsSection("Cards") {
      SettingsRow(
        "Cards shown",
        description: "One card follows the most urgent task. All cards list every task."
      ) {
        Picker(
          "",
          selection: Binding(
            get: { model.overlayState.cardMode },
            set: { model.perform(.setCardMode($0)) }
          )
        ) {
          Text("One").tag(CardDisplayMode.one)
          Text("All").tag(CardDisplayMode.many)
          Text("None").tag(CardDisplayMode.none)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 200)
      }
    }
  }
}

struct PetSettingsPane: View {
  @ObservedObject var model: PetLibraryViewModel
  @State private var previewStatus: TaskVisualStatus = .ready
  @State private var isLinkPromptPresented = false
  @State private var linkText = ""
  @State private var pendingRemoval: PetLibraryViewModel.Row?

  private static let previewStatuses: [TaskVisualStatus] = [
    .ready, .working, .inputNeeded, .finished, .failed,
  ]

  var body: some View {
    header
    if let issue = model.selectionIssue {
      SettingsSection("Action needed") {
        SettingsRow(PetLibraryErrorText.issueText(issue)) {
          Button("Use Original Pet") { Task { await model.select(.original) } }
        }
      }
    }
    SettingsSection("Library") {
      ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
        if index > 0 { Divider() }
        libraryRow(row)
      }
    }
    .task { await model.refresh() }
    .sheet(
      isPresented: Binding(get: { model.review != nil }, set: { if !$0 { model.cancelReview() } })
    ) {
      if let review = model.review {
        PetInstallReviewSheet(model: model, review: review)
      }
    }
    .sheet(isPresented: $isLinkPromptPresented) { linkPrompt }
    .sheet(item: $model.infoRecord) { record in PetRecordInfoSheet(record: record) }
    .alert(
      "Pet library",
      isPresented: Binding(
        get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    ) {
      Button("OK", role: .cancel) { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
    .confirmationDialog(
      "Remove this pet from the library?",
      isPresented: Binding(
        get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
      presenting: pendingRemoval
    ) { row in
      Button("Remove \(row.title)", role: .destructive) {
        Task { await model.remove(recordID: row.id) }
      }
    } message: { _ in
      Text(
        "Only the library copy is removed. The original folder, archive or gallery pet is not changed."
      )
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: DesignTokens.spaceL) {
      Group {
        if model.selection == .none {
          Text("No pet")
            .foregroundStyle(.secondary)
        } else {
          PetPreviewView(package: model.previewPackage, status: previewStatus)
        }
      }
      .frame(width: DesignTokens.settingsPreviewSize, height: DesignTokens.settingsPreviewSize)
      .background(
        RoundedRectangle(cornerRadius: DesignTokens.settingsSectionCornerRadius, style: .continuous)
          .fill(
            Color(nsColor: .controlBackgroundColor).opacity(DesignTokens.settingsSurfaceOpacity))
      )
      VStack(alignment: .leading, spacing: DesignTokens.spaceM) {
        Text(currentTitle)
          .font(.title3.weight(.semibold))
        Picker("Preview state", selection: $previewStatus) {
          ForEach(Self.previewStatuses, id: \.self) { status in
            Text(status.label).tag(status)
          }
        }
        .frame(maxWidth: 240)
        HStack(spacing: DesignTokens.spaceM) {
          PrimaryActionButton("Add Pet…", isEnabled: !model.isBusy) { chooseLocalPackage() }
          Button("Add from Link…") {
            linkText = ""
            isLinkPromptPresented = true
          }
          .disabled(model.isBusy)
          if model.isBusy { ProgressView().controlSize(.small) }
        }
        Text(
          "Package folders with pet.json, codex-pet ZIP files and codex-pets.net links are supported."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
  }

  private var currentTitle: String {
    model.rows.first { $0.selection == model.selection }?.title ?? "Original vector pet"
  }

  @ViewBuilder
  private func libraryRow(_ row: PetLibraryViewModel.Row) -> some View {
    let isSelected = row.selection == model.selection
    let license = PetLibraryErrorText.licenseLabel(row.licenseStatus)
    HStack(spacing: DesignTokens.spaceM) {
      thumbnail(for: row)
      VStack(alignment: .leading, spacing: DesignTokens.spaceXS) {
        Text(row.title)
        Text(row.subtitle)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: DesignTokens.spaceM)
      if row.issue != nil {
        StatusChip(text: "Action needed", tone: .negative)
      } else if row.selection != .none {
        StatusChip(text: license.text, tone: license.tone)
      }
      if isSelected {
        StatusChip(text: "In use", tone: .positive)
      } else {
        Button("Use") { Task { await model.select(row.selection) } }
          .disabled(row.issue == .recordUnreadable)
      }
      if row.record != nil || row.issue != nil {
        Menu {
          if row.record != nil {
            Button("Show in Finder") { model.revealInFinder(recordID: row.id) }
            Button("Get Info") { model.infoRecord = row.record }
          }
          Button("Remove…", role: .destructive) { pendingRemoval = row }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
        .accessibilityLabel("More actions for \(row.title)")
      }
    }
    .frame(minHeight: DesignTokens.settingsRowMinimumHeight)
    .padding(.vertical, DesignTokens.spaceS)
  }

  @ViewBuilder
  private func thumbnail(for row: PetLibraryViewModel.Row) -> some View {
    let size = DesignTokens.settingsThumbnailSize
    Group {
      switch row.selection {
      case .original:
        Image(nsImage: VectorPetRenderer.thumbnail(size: size, status: .ready))
          .resizable()
      case .none:
        Image(systemName: "eye.slash")
          .foregroundStyle(.secondary)
      case .installed(let recordID):
        if let image = model.thumbnails[recordID] {
          Image(nsImage: image).resizable().interpolation(.high)
        } else {
          Image(systemName: "photo").foregroundStyle(.secondary)
        }
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private var linkPrompt: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spaceM) {
      Text("Add a pet from codex-pets.net")
        .font(.headline)
      Text("Paste the pet page link. The download starts only when you continue.")
        .foregroundStyle(.secondary)
      TextField("https://codex-pets.net/#/pets/…", text: $linkText)
        .textFieldStyle(.roundedBorder)
        .frame(width: 360)
      HStack {
        Spacer()
        Button("Cancel") { isLinkPromptPresented = false }
          .keyboardShortcut(.cancelAction)
        PrimaryActionButton(
          "Continue", isEnabled: URL(string: linkText.trimmingCharacters(in: .whitespaces)) != nil
        ) {
          isLinkPromptPresented = false
          let text = linkText
          Task { await stageInput(text) }
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(DesignTokens.settingsPaneInset)
  }

  private func chooseLocalPackage() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.zip, .folder]
    panel.message = "Choose a pet package folder or a codex-pet ZIP file."
    panel.prompt = "Review"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    Task { await stageInput(url.path) }
  }

  private func stageInput(_ input: String) async {
    do {
      let source = try PetPackageSourceResolver.resolve(
        input, relativeTo: FileManager.default.homeDirectoryForCurrentUser)
      await model.stage(source)
    } catch {
      model.errorMessage = PetLibraryErrorText.message(for: error)
    }
  }
}

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
      "No license information was found. You can use this pet locally, but Oh My Agent Pet does not grant any redistribution rights."
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
