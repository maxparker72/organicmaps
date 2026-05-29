import SwiftUI

/// Power-user visual filter builder: chain property conditions with AND/OR and
/// apply them as a visual filter on the map (matching bookmarks stay visible).
/// Value inputs adapt to the property so you can only build valid conditions.
struct FilterView: View {
  @StateObject private var model = FilterModel()
  @StateObject private var tags = TagStore()

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
        }
        Spacer()
        Button("Apply") { model.apply() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.return)
      }

      Text("Filters bookmarks (waypoints). Tracks can't be hidden individually by the engine. Use Show all to reset.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .padding(16)
    .frame(minWidth: 560, minHeight: 320)
  }

  private func options(for property: FilterProperty) -> [String] {
    switch property {
    case .color: return colorOptions
    case .list: return listOptions
    case .type: return typeOptions
    case .tag: return tags.allTags
    default: return []
    }
  }
}

private struct ConditionRow: View {
  @Binding var condition: FilterCondition
  let options: (FilterProperty) -> [String]
  let onRemove: () -> Void

  private static let choiceOps: [StringOp] = [.isExactly, .isNot]

  // .tag is a set-valued property; "is"/"is not" reads as "has"/"does not have".
  static func opLabel(_ op: StringOp, property: FilterProperty) -> String {
    if property == .tag {
      switch op {
      case .isExactly: return "has"
      case .isNot: return "does not have"
      default: break
      }
    }
    return op.rawValue
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
          ForEach(choices, id: \.self) { Text($0).tag($0) }
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
