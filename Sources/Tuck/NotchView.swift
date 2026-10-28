import AppKit
import SwiftUI
import TuckCore

let githubURL = URL(string: "https://github.com/techtheoryio/tuck")!

private let accent = Color(red: 1, green: 0.702, blue: 0.251)  // #FFB340
private let secondary = Color(red: 0.557, green: 0.557, blue: 0.576)  // #8E8E93
private let faded = Color(red: 0.486, green: 0.486, blue: 0.502)  // #7C7C80, still 4.5:1 on black

struct NotchView: View {
    let controller: NotchController

    var body: some View {
        let model = controller.model
        let open = model.phase == .open
        let shape = NotchShape(radius: open ? 24 : 10)
        VStack(spacing: 0) {
            if open {
                TodoPanel(controller: controller)
                    .transition(AnyTransition.asymmetric(
                        insertion: AnyTransition(.blurReplace).animation(NotchController.animation.delay(0.04)),
                        // Gone before the shape shrinks over it, pulled up toward the notch.
                        removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(.easeOut(duration: 0.1))))
            }
        }
        .frame(width: model.size.width, height: model.size.height, alignment: .top)
        .overlay(alignment: .bottom) { ArmingBar(arming: model.phase == .arming) }
        .padding(.horizontal, NotchShape.shoulder)
        .clipShape(shape)
        // Shadow on the plain shape only; shadowing the whole content re-renders every text layer per frame.
        .background(shape.fill(.black).shadow(color: .black.opacity(open ? 0.5 : 0), radius: 30, y: 12))
        .opacity(model.hasNotch || model.phase != .idle ? 1 : 0)  // without a hardware notch, stay invisible until hovered
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .tint(accent)
    }
}

/// Fills up over the hover delay while the pointer rests on the notch.
private struct ArmingBar: View {
    let arming: Bool
    @AppStorage("hoverDelay") private var delay = 1.8
    @State private var progress = 0.0

    var body: some View {
        Capsule()
            .fill(.white.opacity(arming ? 0.16 : 0))
            .frame(width: 64, height: 3)
            .overlay(alignment: .leading) {
                Capsule().fill(accent).frame(width: 64 * progress)
            }
            .clipShape(Capsule())
            .padding(.bottom, 6)
            .accessibilityHidden(true)
            // Its own transaction: `arming` flips inside the notch's spring, which would otherwise fill the bar in 0.3 s.
            .onChange(of: arming) { _, arming in
                if arming {
                    withAnimation(.linear(duration: delay)) { progress = 1 }
                } else {
                    withTransaction(Transaction(animation: nil)) { progress = 0 }
                }
            }
    }
}

private struct TodoPanel: View {
    let controller: NotchController
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = controller.model
        VStack(spacing: 0) {
            HStack {
                AppMenu()
                Spacer()
                Text(countLabel).font(.system(size: 12, weight: .medium)).foregroundStyle(secondary)
            }
            .padding(.horizontal, 20)
            .frame(height: model.notch.height)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.list.items) { todo in
                        TodoRow(todo: todo,
                                toggle: { withAnimation(.snappy) { model.list.toggle(todo.id) } },
                                remove: { withAnimation(NotchController.animation) { model.list.remove(todo.id) } })
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            .frame(height: model.listHeight)
            .overlay {
                if model.list.items.isEmpty {
                    Text("Nothing to do.").font(.system(size: 13)).foregroundStyle(secondary)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(secondary)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5])))
                    .accessibilityHidden(true)
                TextField("New to-do", text: $model.draft, prompt: Text("New to-do…").foregroundStyle(faded))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit {
                        withAnimation(NotchController.animation) {
                            if model.list.add(model.draft) { model.draft = "" }
                        }
                    }
                if model.list.hasDone {
                    Button("Clear done") { withAnimation(NotchController.animation) { model.list.clearDone() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(secondary)
                        // set(), not push/pop: the button disappears under the pointer once it has cleared everything.
                        .onHover { ($0 ? NSCursor.pointingHand : NSCursor.arrow).set() }
                }
            }
            .padding(.horizontal, 20)
            .frame(height: NotchModel.inputHeight)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
        }
        .frame(width: NotchModel.openWidth)
        .foregroundStyle(.white)
        .onAppear { focused = true }
        .onExitCommand { controller.close() }
    }

    private var countLabel: String {
        let list = controller.model.list
        if list.items.isEmpty { return "" }
        return list.openCount == 0 ? "All done" : "\(list.openCount) open"
    }
}

private struct TodoRow: View {
    let todo: Todo
    let toggle: () -> Void
    let remove: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(todo.done ? accent : .white.opacity(0.32), lineWidth: 1.5)
                    .background(Circle().fill(todo.done ? accent : .clear))
                    .overlay {
                        if todo.done {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
                        }
                    }
                    .frame(width: 18, height: 18)
                Text(todo.text)
                    .font(.system(size: 14))
                    .foregroundStyle(todo.done ? faded : .white)
                    .strikethrough(todo.done, color: faded)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: NotchModel.rowHeight)
            .background(.white.opacity(hovered ? 0.06 : 0), in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu { Button("Delete", role: .destructive, action: remove) }
        .accessibilityValue(todo.done ? "Done" : "Open")
    }
}

/// Tuck has no Dock icon and no menu bar item, so settings and quitting live behind the name in the open panel.
private struct AppMenu: View {
    var body: some View {
        Menu {
            Button("Settings…") { SettingsWindow.show() }
            Divider()
            Link("Tuck on GitHub", destination: githubURL)
            Button("Quit Tuck") { NSApp.terminate(nil) }
        } label: {
            Text("Tuck").font(.system(size: 12, weight: .semibold)).tracking(0.24)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// The notch outline: concave shoulders where it meets the top edge, rounded bottom corners.
/// The shoulders sit outside the content, `shoulder` points on each side.
struct NotchShape: Shape {
    static let shoulder: CGFloat = 10
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let s = Self.shoulder
        let r = max(0, min(radius, rect.height - s, (rect.width - 2 * s) / 2))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - s, y: rect.minY + s), control: CGPoint(x: rect.maxX - s, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - s - r, y: rect.maxY), control: CGPoint(x: rect.maxX - s, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + s + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + s, y: rect.maxY - r), control: CGPoint(x: rect.minX + s, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + s, y: rect.minY + s))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.minX + s, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
