import SwiftUI

/// Power-user visual filter builder: chain property conditions with AND/OR and
/// apply them as a visual filter on the map (matching bookmarks stay visible).
/// Value inputs adapt to the property so you can only build valid conditions.
struct FilterView: View {
  @StateObject private var model = FilterModel()
  @StateObject private var tags = TagStore()
  @StateObject private var regions = RegionStore()
  @ObservedObject private var saved = SavedFiltersStore.shared

  // Track which saved filter is currently loaded in the builder, so a re-save
  // updates that filter in place instead of creating a duplicate.
  @State private var loadedSavedId: UUID?
  @State private var saveSheet = false
  @State private var saveName = ""
  @State private var renameSheet: SavedFilter?

  // Real values available to choose from, so a condition can't target something
  // that doesn't exist (which would hide everything).
  private var listOptions: [String] {
    BookmarksManager.shared().sortedUserCategories().map(\.title)
  }
  private var typeOptions: [String] {
    let types = BookmarksManager.shared().sortedUserCategories()
      .flatMap { $0.bookmarks }
      .compactMap { $0.bookmarkType }
      .filter { !$0.isEmpty }
    return Array(Set(types)).sorted()
  }
  private let colorOptions = BookmarkColor.palette.map(\.displayName)

  var body: some View {
    HSplitView {
      savedSidebar
        .frame(minWidth: 180, idealWidth: 200)
      builder
        .frame(minWidth: 560)
    }
    .frame(minWidth: 760, minHeight: 360)
    .sheet(isPresented: $saveSheet) { saveDialog }
    .sheet(item: $renameSheet) { filter in renameDialog(filter) }
  }

  // MARK: - Sidebar

  private var savedSidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Saved Filters").font(.headline)
        Spacer()
      }
      .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
      Divider()
      if saved.filters.isEmpty {
        VStack(spacing: 6) {
          Text("No saved filters yet")
            .font(.subheadline).foregroundStyle(.secondary)
          Text("Build a filter and click Save As… to keep it.")
            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        Spacer()
      } else {
        List {
          ForEach(saved.filters) { filter in savedRow(filter) }
        }
        .listStyle(.sidebar)
      }
    }
    .background(.regularMaterial)
  }

  private func savedRow(_ filter: SavedFilter) -> some View {
    let isLoaded = loadedSavedId == filter.id
    let isActive = saved.activeFilterId == filter.id
    return HStack(spacing: 6) {
      Image(systemName: isActive ? "line.3.horizontal.decrease.circle.fill"
                                 : "line.3.horizontal.decrease.circle")
        .foregroundStyle(isActive ? Color.accentColor : .secondary)
      Text(filter.name).fontWeight(isLoaded ? .semibold : .regular)
      Spacer()
    }
    .contentShape(Rectangle())
    .onTapGesture {
      model.restore(filter)
      loadedSavedId = filter.id
      model.apply()
      saved.setActive(filter.id)
    }
    .contextMenu {
      Button("Apply") {
        model.restore(filter); loadedSavedId = filter.id
        model.apply(); saved.setActive(filter.id)
      }
      Button("Load into Builder") {
        model.restore(filter); loadedSavedId = filter.id
      }
      Button("Rename…") { renameSheet = filter }
      Divider()
      Button("Delete", role: .destructive) {
        saved.delete(filter.id)
        if loadedSavedId == filter.id { loadedSavedId = nil }
      }
    }
  }

  // MARK: - Builder

  private var builder: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 6) {
        Text("Show bookmarks matching")
        Picker("", selection: $model.matchAll) {
          Text("all").tag(true)
          Text("any").tag(false)
        }
        .labelsHidden().fixedSize()
        Text("of:")
      }

      ScrollView {
        VStack(spacing: 8) {
          ForEach($model.conditions) { $condition in
            ConditionRow(condition: $condition,
                         options: options(for:),
                         onRemove: { model.removeCondition(condition) })
          }
        }
      }

      Button { model.addCondition() } label: { Label("Add Condition", systemImage: "plus") }
        .buttonStyle(.borderless)

      Divider()

      HStack {
        Button("Clear Filter") {
          BookmarksManager.shared().setUserCategoriesVisible(true)
          OMBookmarksHelper.showAllItems()
          NotificationCenter.default.post(name: .omItemVisibilityChanged, object: nil)
          saved.setActive(nil)
        }
        Spacer()
        Button("Save As…") {
          saveName = saved.filters.first(where: { $0.id == loadedSavedId })?.name ?? ""
          saveSheet = true
        }
        Button("Update") {
          guard let id = loadedSavedId else { return }
          let name = saved.filters.first(where: { $0.id == id })?.name ?? "Filter"
          saved.save(model.snapshot(name: name, id: id))
        }
        .disabled(loadedSavedId == nil)
        Button("Select Matching") {
          let (bms, trs) = model.matchingIds()
          NotificationCenter.default.post(
            name: .omSelectMatchingFilter, object: nil,
            userInfo: [
              "bookmarks": bms.map { UInt64($0) },
              "tracks": trs.map { UInt64($0) },
            ])
        }
        .help("Open the navigator with every matching item selected for bulk actions")
        Button("Apply") {
          model.apply()
          if let id = loadedSavedId { saved.setActive(id) } else { saved.setActive(nil) }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.return)
      }

      Text("Filters bookmarks (waypoints). Tracks can't be hidden individually by the engine. Use Show all to reset.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .padding(16)
  }

  // MARK: - Dialogs

  private var saveDialog: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Save filter").font(.headline)
      TextField("Name", text: $saveName).textFieldStyle(.roundedBorder)
      HStack {
        Spacer()
        Button("Cancel") { saveSheet = false; saveName = "" }
        Button("Save") {
          let new = model.snapshot(name: saveName)
          saved.save(new)
          loadedSavedId = new.id
          saveSheet = false
          saveName = ""
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 320)
  }

  private func renameDialog(_ filter: SavedFilter) -> some View {
    RenameDialog(initial: filter.name) { newName in
      saved.rename(filter.id, to: newName)
      renameSheet = nil
    } onCancel: {
      renameSheet = nil
    }
  }

  private func options(for property: FilterProperty) -> [String] {
    switch property {
    case .color: return colorOptions
    case .list: return listOptions
    case .type: return typeOptions
    case .tag: return tags.allTags
    case .region: return regions.allRegions
    default: return []
    }
  }
}

private struct RenameDialog: View {
  let initial: String
  let onSave: (String) -> Void
  let onCancel: () -> Void
  @State private var name: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Rename filter").font(.headline)
      TextField("Name", text: $name).textFieldStyle(.roundedBorder)
      HStack {
        Spacer()
        Button("Cancel", action: onCancel)
        Button("Save") { onSave(name) }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 320)
    .onAppear { name = initial }
  }
}

private struct ConditionRow: View {
  @Binding var condition: FilterCondition
  let options: (FilterProperty) -> [String]
  let onRemove: () -> Void

  private static let choiceOps: [StringOp] = [.isExactly, .isNot]

  // .tag and .region are set-valued; "is"/"is not" reads more naturally relabelled.
  static func opLabel(_ op: StringOp, property: FilterProperty) -> String {
    switch property {
    case .tag:
      switch op {
      case .isExactly: return "has"
      case .isNot: return "does not have"
      default: break
      }
    case .region:
      switch op {
      case .isExactly: return "is in"
      case .isNot: return "is not in"
      default: break
      }
    default: break
    }
    return op.rawValue
  }

  // The .region picker stores raw CountryIds (e.g. "United States_California")
  // but should display localized human names.
  static func choiceLabel(_ value: String, property: FilterProperty) -> String {
    if property == .region {
      return OMBookmarksHelper.displayName(forRegion: value)
    }
    return value
  }

  var body: some View {
    HStack(spacing: 8) {
      Picker("", selection: $condition.property) {
        ForEach(FilterProperty.allCases) { Text($0.rawValue).tag($0) }
      }
      .labelsHidden().frame(width: 130)
      .onChange(of: condition.property) { _, newValue in applyDefaults(for: newValue) }

      operatorPicker
      valueControl

      Button(role: .destructive, action: onRemove) { Image(systemName: "minus.circle") }
        .buttonStyle(.borderless)
    }
  }

  // Fixed column widths so every condition row aligns regardless of content.
  private static let operatorWidth: CGFloat = 150

  @ViewBuilder private var operatorPicker: some View {
    Group {
      switch condition.property.kind {
      case .number:
        Picker("", selection: $condition.numberOp) {
          ForEach(NumberOp.allCases) { Text($0.rawValue).tag($0) }
        }
      case .choice:
        Picker("", selection: $condition.stringOp) {
          ForEach(Self.choiceOps) { op in Text(Self.opLabel(op, property: condition.property)).tag(op) }
        }
      case .text:
        Picker("", selection: $condition.stringOp) {
          ForEach(StringOp.allCases) { Text($0.rawValue).tag($0) }
        }
      }
    }
    .labelsHidden()
    .frame(width: Self.operatorWidth)
  }

  @ViewBuilder private var valueControl: some View {
    Group {
      switch condition.property.kind {
      case .choice:
        let choices = options(condition.property)
        Picker("", selection: $condition.value) {
          if choices.isEmpty { Text("—").tag("") }
          ForEach(choices, id: \.self) { value in
            Text(Self.choiceLabel(value, property: condition.property)).tag(value)
          }
        }
        .labelsHidden()
      case .number:
        HStack(spacing: 4) {
          TextField("0", text: $condition.value)
            .textFieldStyle(.roundedBorder)
            .onChange(of: condition.value) { _, newValue in
              condition.value = newValue.filter { $0.isNumber || $0 == "." }
            }
          Text("m").foregroundStyle(.secondary)
        }
      case .text:
        TextField("value", text: $condition.value).textFieldStyle(.roundedBorder)
      }
    }
    .frame(maxWidth: .infinity)
  }

  private func applyDefaults(for property: FilterProperty) {
    switch property.kind {
    case .text:
      condition.stringOp = .contains
      condition.value = ""
    case .choice:
      condition.stringOp = .isExactly
      condition.value = options(property).first ?? ""
    case .number:
      condition.numberOp = .gt
      condition.value = ""
    }
  }
}
