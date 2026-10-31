import AppKit
import ServiceManagement
import SwiftUI

struct SearchView: View {
    @ObservedObject var model: SearchModel
    let openPermissions: () -> Void
    let showSetup: () -> Void
    let chooseDatabase: () -> Void
    let resetDatabase: () -> Void
    let quit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hoveredRow: Int?
    @State private var isOptionsHovered = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass").font(.system(size: 25, weight: .light)).foregroundStyle(.secondary)
                SearchField(model: model).frame(height: 38)
                if model.searching { ProgressView().controlSize(.small) }
                Text("esc").font(.caption.monospaced()).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }.padding(.horizontal, 24).padding(.vertical, 22)
            Divider().opacity(0.45)
            if let error = model.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                    Button("Open Full Disk Access settings", action: openPermissions)
                        .buttonStyle(.link)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(Array(model.suggestions.enumerated()), id: \.offset) { index, suggestion in
                            row(index: index, icon: suggestion.icon, faviconURL: suggestion.faviconURL, title: suggestion.title,
                                subtitle: suggestion.subtitle)
                        }
                        if model.rowCount == 0 && !model.searching && model.error == nil {
                            Text("Your recent Safari pages will appear here.")
                                .foregroundStyle(.secondary).padding(32)
                        }
                    }.padding(10)
                }
                .onChange(of: model.selected) { value in proxy.scrollTo(value, anchor: .center) }
            }
            Divider().opacity(0.45)
            HStack {
                Text("SAFARI QUICK SEARCH 1.6").font(.system(size: 10, weight: .semibold, design: .rounded))
                Spacer()
                Menu {
                    Toggle("Launch at Login", isOn: Binding(
                        get: { model.loginItemStatus == .enabled },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    .disabled(model.updatingLoginItem)
                    if model.loginItemStatus == .requiresApproval {
                        Button("Approve in Login Items Settings…") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                    Divider()
                    Button("Full Disk Access Setup…", action: showSetup)
                    Button("Choose History Database…", action: chooseDatabase)
                    Button("Use Default Safari Database", action: resetDatabase)
                    Divider()
                    Button("Quit Safari Quick Search", action: quit)
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .opacity(isOptionsHovered ? 0.5 : 0.25)
                .frame(width: 36, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isOptionsHovered ? (contrast == .increased ? 0.18 : 0.08) : 0))
                }
                .contentShape(Rectangle())
                .onHover { isOptionsHovered = $0 }
                .onDisappear { isOptionsHovered = false }
                .help("Options")
                .accessibilityLabel("Options")
            }.foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(width: 700, height: 500)
        .modifier(PanelGlassSurface())
        .alert("Could Not Update Launch at Login", isPresented: Binding(
            get: { model.loginItemError != nil },
            set: { if !$0 { model.loginItemError = nil } }
        )) {
            Button("OK", role: .cancel) { model.loginItemError = nil }
        } message: {
            Text(model.loginItemError ?? "")
        }
    }

    private func row(index: Int, icon: String, faviconURL: URL?, title: String, subtitle: String) -> some View {
        Button {
            model.selected = index
            model.openSelection()
        } label: {
            HStack(spacing: 14) {
                SiteIcon(url: faviconURL, placeholder: icon).frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if model.selected == index { Image(systemName: "return").foregroundStyle(.secondary) }
            }.padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(model.selected == index
                              ? Color.accentColor.opacity(contrast == .increased ? 0.35 : 0.20)
                              : Color.primary.opacity(hoveredRow == index ? 0.06 : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(model.selected == index
                                      ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 0.75)
                }
        }.buttonStyle(.plain).id(index)
            .onHover { inside in
                if inside { hoveredRow = index }
                else if hoveredRow == index { hoveredRow = nil }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: model.selected == index)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredRow == index)
            .accessibilityLabel("\(title), \(subtitle)")
    }
}

// One system glass surface for the floating panel; rows use simple tint
// highlights rather than stacking multiple refractive glass layers.
private struct PanelGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08), .white.opacity(0.20)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                }
        }
    }
}

// AppKit owns text editing, IME composition and keyboard navigation.
struct SearchField: NSViewRepresentable {
    @ObservedObject var model: SearchModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Search history, enter a URL, or search Google"
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 23, weight: .regular)
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search history, enter a URL, or search Google")
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != model.query { field.stringValue = model.query }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: SearchModel
        init(_ model: SearchModel) { self.model = model }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            model.query = field.currentEditor()?.string ?? field.stringValue
            model.refresh()
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            // Let the input method finish composing before interpreting navigation.
            if textView.hasMarkedText() { return false }
            switch selector {
            case #selector(NSResponder.moveDown(_:)): model.move(1)
            case #selector(NSResponder.moveUp(_:)): model.move(-1)
            case #selector(NSResponder.insertNewline(_:)): model.openSelection()
            case #selector(NSResponder.cancelOperation(_:)): model.dismiss?()
            default: return false
            }
            return true
        }
    }
}


// Cache only in memory. No third-party icon service or Safari cookies.
@MainActor
private final class FaviconStore {
    static let shared = FaviconStore()
    private let images = NSCache<NSURL, NSImage>()
    private var missing = Set<URL>()
    private var requests: [URL: Task<Data?, Never>] = [:]
    private let session: URLSession

    private init() {
        images.countLimit = 200
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: configuration)
    }

    func image(for url: URL) async -> NSImage? {
        if let image = images.object(forKey: url as NSURL) { return image }
        if missing.contains(url) { return nil }
        if let request = requests[url] {
            let data = await request.value
            return data.flatMap { NSImage(data: $0) }
        }
        let session = session
        let request = Task<Data?, Never> {
            do {
                var request = URLRequest(url: url)
                request.setValue("image/*", forHTTPHeaderField: "Accept")
                let (bytes, response) = try await session.bytes(for: request)
                guard let response = response as? HTTPURLResponse,
                      response.statusCode == 200,
                      response.url?.scheme == "https",
                      response.expectedContentLength <= 262_144 else { return nil }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < 262_144 else { return nil }
                    data.append(byte)
                }
                return data
            } catch { return nil }
        }
        requests[url] = request
        let data = await request.value
        let decoded = data.flatMap { NSImage(data: $0) }
        let image = decoded?.isValid == true ? decoded : nil
        requests[url] = nil
        if let image { images.setObject(image, forKey: url as NSURL) }
        else {
            if missing.count >= 500 { missing.removeAll() }
            missing.insert(url)
        }
        return image
    }
}

private struct SiteIcon: View {
    let url: URL?
    let placeholder: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 20, height: 20)
            } else {
                Image(systemName: placeholder).font(.system(size: 18)).foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            guard let url else { return }
            let loaded = await FaviconStore.shared.image(for: url)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
