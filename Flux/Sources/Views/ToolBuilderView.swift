import SwiftUI

struct ToolBuilderView: View {
    @State private var tools: [CustomTool] = []
    @State private var selectedToolId: UUID?
    @State private var editingTool: CustomTool?

    private let toolsDirectory: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".flux/tools", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var body: some View {
        NavigationSplitView {
            List(tools, selection: $selectedToolId) { tool in
                HStack {
                    Image(systemName: tool.icon)
                        .frame(width: 20)
                    Text(tool.name)
                }
                .tag(tool.id)
            }
            .navigationTitle("Tools")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createNewTool()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        } detail: {
            if let selectedToolId,
               let index = tools.firstIndex(where: { $0.id == selectedToolId }) {
                ToolEditorView(tool: $tools[index], onSave: { saveTool(tools[index]) }, onDelete: { deleteTool(at: index) })
            } else {
                Text("Select or create a tool")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { loadTools() }
    }

    private func createNewTool() {
        let tool = CustomTool(
            name: "New Tool",
            icon: "hammer",
            description: "",
            prompt: "",
            variables: [],
            actions: []
        )
        tools.append(tool)
        selectedToolId = tool.id
        saveTool(tool)
    }

    private func loadTools() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: toolsDirectory, includingPropertiesForKeys: nil
        ) else { return }

        tools = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> CustomTool? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(CustomTool.self, from: data)
            }
    }

    private func saveTool(_ tool: CustomTool) {
        let url = toolsDirectory.appendingPathComponent("\(tool.id.uuidString).json")
        guard let data = try? JSONEncoder().encode(tool) else { return }
        try? data.write(to: url)
    }

    private func deleteTool(at index: Int) {
        let tool = tools[index]
        let url = toolsDirectory.appendingPathComponent("\(tool.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        tools.remove(at: index)
        selectedToolId = nil
    }
}

struct ToolEditorView: View {
    @Binding var tool: CustomTool
    var onSave: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Form {
            Section("General") {
                TextField("Name", text: $tool.name)
                TextField("Icon (SF Symbol)", text: $tool.icon)
                TextField("Description", text: $tool.description)
            }

            Section("Prompt Template") {
                TextEditor(text: $tool.prompt)
                    .frame(minHeight: 100)
                    .font(.system(.body, design: .monospaced))

                Text("Variables: {{screen}}, {{clipboard}}, {{selected_text}}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Context Variables") {
                ForEach(CustomTool.ContextVariable.allCases, id: \.rawValue) { variable in
                    Toggle(variable.rawValue, isOn: Binding(
                        get: { tool.variables.contains(variable) },
                        set: { included in
                            if included {
                                tool.variables.append(variable)
                            } else {
                                tool.variables.removeAll { $0 == variable }
                            }
                        }
                    ))
                }
            }

            Section("Hotkey") {
                TextField("Keys (e.g. cmd+shift+s)", text: Binding(
                    get: { tool.trigger?.keys ?? "" },
                    set: { keys in
                        if keys.isEmpty {
                            tool.trigger = nil
                        } else {
                            tool.trigger = ToolTrigger(type: .hotkey, keys: keys)
                        }
                    }
                ))
            }

            Section {
                HStack {
                    Button("Save") {
                        onSave()
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button("Delete", role: .destructive) {
                        onDelete()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tool.name)
    }
}
