import SwiftUI

/// Sheet shown by ImportCoordinator before a multi-file or folder import:
/// lets the user pick a target list (otherwise each file becomes its own
/// auto-named list), an optional tag applied to every imported item, and
/// an optional project to add them to.
struct ImportDestinationSheet: View {
  let fileCount: Int
  let ignoredCount: Int
  @ObservedObject var bookmarksModel: BookmarksNavigatorModel
  @ObservedObject var projectsModel: ProjectModel
  @ObservedObject var tagStore: TagStore
  let onConfirm: (ImportCoordinator.Options) -> Void
  let onCancel: () -> Void

  // 0 is reserved as "no target" — kml::kInvalidMarkGroupId is also 0 so the
  // engine wouldn't accept it as a move destination either.
  @State private var targetListId: MWMMarkGroupID = 0
  @State private var tag: String = ""
  @State private var projectId: MWMMarkGroupID = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Import \(fileCount) \(fileCount == 1 ? "file" : "files")")
        .font(.title2.weight(.semibold))
      if ignoredCount > 0 {
        Text("\(ignoredCount) unsupported \(ignoredCount == 1 ? "item" : "items") in the chosen folder will be skipped.")
          .font(.caption).foregroundStyle(.secondary)
      }

      Divider()

      Form {
        Picker("Destination", selection: $targetListId) {
          Text("Keep as new lists").tag(MWMMarkGroupID(0))
          if !bookmarksModel.lists.isEmpty {
            Divider()
            ForEach(bookmarksModel.lists, id: \.categoryId) { list in
              Text(list.title).tag(list.categoryId)
            }
          }
        }

        HStack {
          TextField("Tag", text: $tag, prompt: Text("Optional"))
          if !tagStore.allTags.isEmpty {
            Menu {
              ForEach(tagStore.allTags, id: \.self) { existing in
                Button(existing) { tag = existing }
              }
            } label: { Image(systemName: "tag") }
            .menuStyle(.borderlessButton).fixedSize()
          }
        }

        Picker("Project", selection: $projectId) {
          Text("None").tag(MWMMarkGroupID(0))
          if !projectsModel.projects.isEmpty {
            Divider()
            ForEach(projectsModel.projects) { project in
              Text(project.name).tag(project.categoryId)
            }
          }
        }
        .disabled(projectsModel.projects.isEmpty)
      }
      .formStyle(.grouped)

      Spacer().frame(height: 0)

      HStack {
        Spacer()
        Button("Cancel", action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button("Import") {
          let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
          onConfirm(ImportCoordinator.Options(
            targetListId: targetListId == 0 ? nil : targetListId,
            tag: trimmedTag.isEmpty ? nil : trimmedTag,
            projectId: projectId == 0 ? nil : projectId))
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(20)
    .frame(width: 460)
  }
}
