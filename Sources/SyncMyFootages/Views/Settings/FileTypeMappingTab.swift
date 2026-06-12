import SwiftUI

struct FileTypeMappingTab: View {
    @State private var mapping = FileTypeMapping.load()
    @State private var newCategoryName = ""
    @State private var newExtension = ""
    @State private var editingCategoryIndex: Int?
    @State private var hasChanges = false

    var body: some View {
        Form {
            Section("Type Mapping") {
                Text("Maps file extensions to folder names for the {type} token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(mapping.categories.enumerated()), id: \.element.id) { index, category in
                    categoryRow(index: index, category: category)
                    if index < mapping.categories.count - 1 {
                        Divider()
                    }
                }

                // Add new category
                HStack {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.green)
                    TextField("New type name...", text: $newCategoryName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    Button("Add") {
                        addCategory()
                    }
                    .disabled(newCategoryName.isEmpty || mapping.categories.contains { $0.folderName == newCategoryName })
                }
            }

            Section("Unknown Extensions") {
                Picker("Fallback folder", selection: $mapping.fallbackFolder) {
                    Text("others").tag("others")
                    ForEach(mapping.categories) { cat in
                        Text(cat.folderName).tag(cat.folderName)
                    }
                }
                .onChange(of: mapping.fallbackFolder) { hasChanges = true }
            }

            Section {
                HStack {
                    Button("Reset to defaults") {
                        mapping = .defaultMapping
                        mapping.save()
                        hasChanges = false
                    }
                    .foregroundStyle(.red)

                    Spacer()

                    if hasChanges {
                        Button("Save") {
                            mapping.save()
                            hasChanges = false
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("Saved")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func categoryRow(index: Int, category: FileTypeMapping.Category) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: icon + folder name field + delete
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 16)

                TextField("folder", text: Binding(
                    get: { mapping.categories[index].folderName },
                    set: {
                        mapping.categories[index].folderName = $0
                        hasChanges = true
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .font(.body.monospaced())

                // Extensions inline
                FlowLayout(spacing: 4) {
                    ForEach(category.extensions, id: \.self) { ext in
                        extensionBadge(ext, categoryIndex: index)
                    }

                    addExtensionButton(categoryIndex: index)
                }

                Spacer()

                Button {
                    mapping.categories.remove(at: index)
                    hasChanges = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func extensionBadge(_ ext: String, categoryIndex: Int) -> some View {
        HStack(spacing: 3) {
            Text(ext)
                .font(.caption.monospaced().bold())
            Button {
                removeExtension(ext, fromCategoryAt: categoryIndex)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder
    private func addExtensionButton(categoryIndex: Int) -> some View {
        if editingCategoryIndex == categoryIndex {
            HStack(spacing: 2) {
                TextField("EXT", text: $newExtension)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 55)
                    .font(.caption.monospaced())
                    .onSubmit { addExtension(toCategoryAt: categoryIndex) }
                Button {
                    addExtension(toCategoryAt: categoryIndex)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.borderless)
                Button {
                    editingCategoryIndex = nil
                    newExtension = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        } else {
            Button {
                editingCategoryIndex = categoryIndex
                newExtension = ""
            } label: {
                Image(systemName: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
            .help("Add extension")
        }
    }

    // MARK: - Actions

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return }
        mapping.categories.append(FileTypeMapping.Category(folderName: name, extensions: []))
        newCategoryName = ""
        hasChanges = true
    }

    private func removeExtension(_ ext: String, fromCategoryAt index: Int) {
        mapping.categories[index].extensions.removeAll { $0 == ext }
        hasChanges = true
    }

    private func addExtension(toCategoryAt index: Int) {
        let ext = newExtension.trimmingCharacters(in: .whitespaces).uppercased()
        guard !ext.isEmpty else { return }
        for i in mapping.categories.indices {
            mapping.categories[i].extensions.removeAll { $0 == ext }
        }
        mapping.categories[index].extensions.append(ext)
        newExtension = ""
        editingCategoryIndex = nil
        hasChanges = true
    }
}

/// Simple flow layout for extension badges
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
