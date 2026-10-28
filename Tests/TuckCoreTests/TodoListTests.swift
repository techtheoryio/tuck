import Foundation
import Testing
@testable import TuckCore

@Test func addTrimsAndIgnoresBlank() {
    var list = TodoList()
    let added = list.add("  Call Lea \n"), blank = list.add("   ")
    #expect(added && !blank)
    #expect(list.items.map(\.text) == ["Call Lea"])
}

@Test func toggleRemoveAndClearDone() {
    var list = TodoList()
    list.add("a"); list.add("b"); list.add("c")
    list.toggle(list.items[0].id)
    list.toggle(list.items[2].id)
    #expect(list.openCount == 1 && list.hasDone)
    list.remove(list.items[1].id)
    #expect(list.items.map(\.text) == ["a", "c"])
    list.clearDone()
    #expect(list.items.isEmpty && !list.hasDone)
}

@Test func roundTripsAndKeepsBrokenFiles() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "todos.json")

    #expect(TodoList.load(from: url) == TodoList())
    var list = TodoList()
    list.add("Ship Tuck")
    try list.save(to: url)
    #expect(TodoList.load(from: url) == list)

    try Data("not json".utf8).write(to: url)
    #expect(TodoList.load(from: url) == TodoList())
    #expect(try String(contentsOf: url.appendingPathExtension("broken"), encoding: .utf8) == "not json")
}
