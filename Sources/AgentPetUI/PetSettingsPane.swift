import AgentPetLibrary
import AgentPetSprites
import AppKit
import SwiftUI

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
