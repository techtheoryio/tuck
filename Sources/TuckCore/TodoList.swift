import Foundation

public struct Todo: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var text: String
    public var done = false

    public init(text: String, done: Bool = false) {
        self.text = text
        self.done = done
    }
}

public struct TodoList: Codable, Equatable, Sendable {
    public var items: [Todo]

    public init(items: [Todo] = []) { self.items = items }

    public var openCount: Int { items.count { !$0.done } }
    public var hasDone: Bool { items.contains { $0.done } }

    /// Appends a trimmed to-do; blank text is ignored. Returns whether one was added.
    @discardableResult
    public mutating func add(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        items.append(Todo(text: text))
        return true
    }

    public mutating func toggle(_ id: Todo.ID) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].done.toggle() }
    }

    public mutating func remove(_ id: Todo.ID) { items.removeAll { $0.id == id } }

    public mutating func clearDone() { items.removeAll { $0.done } }

    /// A missing file is an empty list. An unreadable one is moved aside to `<name>.broken` rather than
    /// overwritten by the next save.
    public static func load(from url: URL) -> TodoList {
        guard let data = try? Data(contentsOf: url) else { return TodoList() }
        do {
            return try JSONDecoder().decode(TodoList.self, from: data)
        } catch {
            let aside = url.appendingPathExtension("broken")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            return TodoList()
        }
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
