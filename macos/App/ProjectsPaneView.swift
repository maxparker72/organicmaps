import SwiftUI
import UniformTypeIdentifiers

/// Drag payload used between the bookmarks navigator (source) and the projects
/// pane (drop target). Stringified to avoid Info.plist UTType registration.
struct DraggableEntity {
  enum Kind: String { case bookmark, track }
  let kind: Kind
  let id: UInt64

  var transferString: String { "om-entity:\(kind.rawValue):\(id)" }

  init(kind: Kind, id: UInt64) { self.kind = kind; self.id = id }

  init?(transferString s: String) {
    let parts = s.split(separator: ":")
    guard parts.count == 3, parts[0] == "om-entity",
          let kind = Kind(rawValue: String(parts[1])),
          let id = UInt64(parts[2]) else { return nil }
    self.init(kind: kind, id: id)
  }
}

/// Second leading-edge pane (alongside NavigatorView). Lists projects as
/// drop targets; primary interaction is dragging bookmarks/tracks from the
/// navigator into a project row. Selecting a project reveals a details
/// section for renaming and dates.
struct ProjectsPaneView: View {
  @ObservedObject var projects: ProjectModel
  @ObservedObject var bookmarks: BookmarksNavigatorModel
  let onHide: () -> Void

  @State private var expanded: Set<MWMMarkGroupID> = []
  @State private var showNew = false
  @State private var newName = ""
  @State private var dropTargeted: MWMMarkGroupID?
  @State private var selectedProjectId: MWMMarkGroupID?

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      List {
        ForEach(projects.projects) { project in
          projectRow(project)
          if expanded.contains(project.categoryId) {
            memberRows(project)
          }
          if selectedProjectId == project.categoryId {
            projectDetails(project)
          }
        }
      }
      .listStyle(.sidebar)
      if projects.projects.isEmpty {
        emptyState
      }
    }
    .frame(width: 300)
    .background(.regularMaterial)
    .alert("New Project", isPresented: $showNew) {
      TextField("Name", text: $newName)
      Button("Create") {
        let id = projects.createProject(name: newName)
        if id != 0 { expanded.insert(id) }
        newName = ""
      }
      Button("Cancel", role: .cancel) { newName = "" }
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Text("Projects").font(.headline)
      Spacer()
      Button { showNew = true } label: { Image(systemName: "plus") }
        .buttonStyle(.borderless).help("New project")
      Button(action: onHide) { Image(systemName: "sidebar.left") }
        .buttonStyle(.borderless).help("Hide projects")
    }
    .padding(16)
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "folder.badge.plus").font(.largeTitle).foregroundStyle(.secondary)
      Text("No projects yet").font(.subheadline).foregroundStyle(.secondary)
      Text("Create one and drag bookmarks or tracks into it.")
        .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
    .frame(maxWidth: .infinity).padding(.vertical, 24)
  }

  private func projectRow(_ project: Project) -> some View {
    let isolated = projects.isIsolated(project)
    return HStack(spacing: 6) {
      Button { toggleExpanded(project.categoryId) } label: {
        Image(systemName: expanded.contains(project.categoryId) ? "chevron.down" : "chevron.right")
          .frame(width: 12)
      }
      .buttonStyle(.borderless)

      Button {
        selectedProjectId = selectedProjectId == project.categoryId ? nil : project.categoryId
      } label: {
        HStack {
          Image(systemName: "folder").foregroundStyle(.secondary)
          Text(project.name).fontWeight(.medium)
          Spacer()
          Text("\(projects.memberCount(project))")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      .buttonStyle(.plain)

      // Isolation: snapshot current map visibility, then show only this project.
      // Toggle again to restore.
      Button { projects.toggleIsolation(project) } label: {
        Image(systemName: "dot.viewfinder")
          .foregroundStyle(isolated ? Color.accentColor : .secondary)
      }
      .buttonStyle(.borderless)
      .help(isolated ? "Stop isolating (restore visibility)" : "Isolate (show only this project on the map)")
    }
    .padding(.vertical, 2)
    .background(rowBackground(isolated: isolated, project: project))
    .onDrop(of: [.text], isTargeted: Binding(
      get: { dropTargeted == project.categoryId },
      set: { dropTargeted = $0 ? project.categoryId : nil }
    )) { providers in
      handleDrop(providers: providers, project: project)
    }
    .contextMenu {
      Button(isolated ? "Stop Isolating" : "Isolate") { projects.toggleIsolation(project) }
      Button("Rename") { selectedProjectId = project.categoryId }
      Button("Delete Project", role: .destructive) { projects.delete(project) }
    }
    .swipeActions(edge: .trailing) {
      Button(role: .destructive) { projects.delete(project) } label: { Label("Delete", systemImage: "trash") }
    }
  }

  private func rowBackground(isolated: Bool, project: Project) -> Color {
    if dropTargeted == project.categoryId { return Color.accentColor.opacity(0.18) }
    if isolated { return Color.accentColor.opacity(0.08) }
    return Color.clear
  }

  @ViewBuilder
  private func memberRows(_ project: Project) -> some View {
    let memberBookmarkIds = Set(projects.bookmarkIds(in: project))
    let memberTrackIds = Set(projects.trackIds(in: project))
    let bookmarkObjs = bookmarks.lists.flatMap { $0.bookmarks }.filter { memberBookmarkIds.contains($0.bookmarkId) }
    let trackObjs = bookmarks.lists.flatMap { $0.tracks }.filter { memberTrackIds.contains($0.trackId) }

    if bookmarkObjs.isEmpty && trackObjs.isEmpty {
      Text("Empty — drag items here").font(.caption).foregroundStyle(.tertiary)
        .padding(.leading, 32).padding(.vertical, 4)
    } else {
      ForEach(bookmarkObjs, id: \.bookmarkId) { bm in
        memberBookmarkRow(bm, project: project)
      }
      ForEach(trackObjs, id: \.trackId) { tr in
        memberTrackRow(tr, project: project)
      }
    }
  }

  private func memberBookmarkRow(_ bm: Bookmark, project: Project) -> some View {
    HStack(spacing: 8) {
      Circle().fill(Color(nsColor: bm.bookmarkColor)).frame(width: 8, height: 8)
      Text(bm.bookmarkName).lineLimit(1)
      Spacer()
      Button { projects.removeBookmark(bm.bookmarkId, from: project) } label: {
        Image(systemName: "minus.circle").foregroundStyle(.secondary)
      }
      .buttonStyle(.borderless).help("Remove from project")
    }
    .padding(.leading, 32)
  }

  private func memberTrackRow(_ tr: Track, project: Project) -> some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 1).fill(Color(nsColor: tr.trackColor)).frame(width: 12, height: 3)
      Text(tr.trackName).lineLimit(1)
      Spacer()
      Button { projects.removeTrack(tr.trackId, from: project) } label: {
        Image(systemName: "minus.circle").foregroundStyle(.secondary)
      }
      .buttonStyle(.borderless).help("Remove from project")
    }
    .padding(.leading, 32)
  }

  @ViewBuilder
  private func projectDetails(_ project: Project) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Name").font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
        TextField("Name", text: Binding(
          get: { project.name },
          set: { projects.rename(project, to: $0) }
        ))
        .textFieldStyle(.roundedBorder)
      }
      HStack {
        Text("Start").font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
        DatePicker("", selection: Binding(
          get: { project.startDate ?? Date() },
          set: { projects.setStartDate($0, project: project) }
        ), displayedComponents: .date)
        .labelsHidden()
        if project.startDate != nil {
          Button { projects.setStartDate(nil, project: project) } label: { Image(systemName: "xmark.circle") }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
      }
      HStack {
        Text("End").font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
        DatePicker("", selection: Binding(
          get: { project.endDate ?? Date() },
          set: { projects.setEndDate($0, project: project) }
        ), displayedComponents: .date)
        .labelsHidden()
        if project.endDate != nil {
          Button { projects.setEndDate(nil, project: project) } label: { Image(systemName: "xmark.circle") }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
      }
    }
    .padding(.horizontal, 18).padding(.vertical, 8)
    .background(Color.secondary.opacity(0.06))
  }

  private func toggleExpanded(_ id: MWMMarkGroupID) {
    if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
  }

  private func handleDrop(providers: [NSItemProvider], project: Project) -> Bool {
    var any = false
    for provider in providers {
      if !provider.canLoadObject(ofClass: NSString.self) { continue }
      _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
        guard let s = obj as? String, let entity = DraggableEntity(transferString: s) else { return }
        DispatchQueue.main.async {
          switch entity.kind {
          case .bookmark: projects.addBookmark(MWMMarkID(entity.id), to: project)
          case .track:    projects.addTrack(MWMTrackID(entity.id), to: project)
          }
          expanded.insert(project.categoryId)
        }
      }
      any = true
    }
    return any
  }
}
