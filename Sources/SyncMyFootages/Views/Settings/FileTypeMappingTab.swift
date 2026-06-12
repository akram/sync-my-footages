import SwiftUI

struct FileTypeMappingTab: View {
    @State private var mapping = FileTypeMapping.load()
    @State private var newCategoryName = ""
    @State private var newExtension = ""
    @State private var editingCategoryIndex: Int?
    @State private var hasChanges = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text("When using `{type}` in the pattern, files are sorted into folders by extension.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Table header
                    HStack {
                        Text("Folder Name")
                            .frame(width: 100, alignment: .leading)
                        Text("Extensions")
                        Spacer()
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                    // Rows
                    ForEach(Array(mapping.categories.enumerated()), id: \.element.id) { index, category in
                        HStack(alignment: .center, spacing: 8) {
                            // Folder name
                            LeftAlignedTextField(
                                text: Binding(
                                    get: { mapping.categories[index].folderName },
                                    set: { mapping.categories[index].folderName = $0 }
                                ),
                                onCommit: { hasChanges = true }
                            )
                            .frame(width: 100, height: 22)

                            // Extensions
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
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    // Add row
                    HStack(spacing: 8) {
                        LeftAlignedTextField(
                            text: $newCategoryName,
                            onCommit: { addCategory() }
                        )
                        .frame(width: 100, height: 22)

                        Button {
                            addCategory()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.borderless)
                        .disabled(newCategoryName.isEmpty || mapping.categories.contains { $0.folderName == newCategoryName })

                        Spacer()
                    }
                } header: {
                    Text("Type Mapping")
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
    }

    private func extensionBadge(_ ext: String, categoryIndex: Int) -> some View {
        HStack(spacing: 3) {
            Text(ext)
                .font(.caption.monospaced().bold())
            Button {
                mapping.categories[categoryIndex].extensions.removeAll { $0 == ext }
                hasChanges = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
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
                        .foregroundStyle(.green)
                }
                .buttonStyle(.borderless)
                Button {
                    editingCategoryIndex = nil
                    newExtension = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
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
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
            .frame(height: 26)
        }
    }

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return }
        mapping.categories.append(FileTypeMapping.Category(folderName: name, extensions: []))
        newCategoryName = ""
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

/// NSTextField wrapper that properly left-aligns text
struct LeftAlignedTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void = {}

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.isBordered = true
        tf.isBezeled = true
        tf.bezelStyle = .roundedBezel
        tf.alignment = .left
        tf.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tf.delegate = context.coordinator
        tf.lineBreakMode = .byTruncatingTail
        tf.usesSingleLineMode = true
        tf.cell?.truncatesLastVisibleLine = true
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: LeftAlignedTextField
        init(_ parent: LeftAlignedTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.onCommit()
        }
    }
}

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
