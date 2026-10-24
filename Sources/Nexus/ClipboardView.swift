import SwiftUI
import AppKit
import NexusCore
import UniformTypeIdentifiers

struct ClipboardView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var clip: ClipboardModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                TextField("Type to filter entries…", text: $clip.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .focused($focused)
                    .onKeyPress(.downArrow) { model.key(.down); return .handled }
                    .onKeyPress(.upArrow) { model.key(.up); return .handled }
                    .onKeyPress(.return) { model.key(.enter); return .handled }
                    .onKeyPress(.escape) { model.key(.escape); return .handled }
                Menu {
                    ForEach(ClipFilter.allCases, id: \.self) { f in
                        Button { clip.filter = f } label: { Label(f.rawValue, systemImage: f.symbol) }
                    }
                } label: {
                    Label(clip.filter.rawValue, systemImage: clip.filter.symbol).font(.system(size: 14)).foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .padding(.horizontal, 22)
            .frame(height: 62)

            HStack(spacing: 0) {
                list.frame(width: 290)
                Divider().opacity(0.3)
                detail.frame(maxWidth: .infinity)
            }

            Footer(moduleIcon: "doc.on.clipboard.fill", moduleName: "Clipboard History", primary: clip.primaryLabel,
                   onActions: { model.toggleActions(); clip.focusTick += 1 })
        }
        .refocusOnAppear($focused)
        .onChange(of: clip.focusTick) { _, _ in focused = true }
    }

    // MARK: list

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(clip.items.enumerated()), id: \.element.id) { i, c in
                        if i == 0 || ClipboardModel.group(for: clip.items[i - 1]) != ClipboardModel.group(for: c) {
                            SectionHeader(title: ClipboardModel.group(for: c), first: i == 0)
                        }
                        ClipRow(clip: c, selected: i == clip.selection)
                            .id(c.id)
                            .onTapGesture { clip.selection = i; clip.focusTick += 1 }
                    }
                    if clip.items.isEmpty {
                        Text(clip.query.isEmpty ? "Nothing copied yet" : "No matches")
                            .foregroundStyle(.secondary).padding(22)
                    }
                }
                .padding(.horizontal, 8)
            }
            .onChange(of: clip.selection) { _, new in
                if clip.items.indices.contains(new) { proxy.scrollTo(clip.items[new].id) }
            }
        }
    }

    // MARK: detail

    @ViewBuilder private var detail: some View {
        if let c = clip.selected {
            VStack(alignment: .leading, spacing: 10) {
                preview(c).frame(maxWidth: .infinity, minHeight: 130, maxHeight: .infinity)
                if c.isTruncated {
                    Text("Preview shows the first \(c.text.count.formatted()) characters. The full text is pasted.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text("Information").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                info(c)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        } else {
            Color.clear
        }
    }

    @ViewBuilder private func preview(_ c: Clip) -> some View {
        switch c.kind {
        case .image:
            if let p = c.imagePath, let img = NSImage(contentsOfFile: p) {
                Image(nsImage: img).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { Text("Image unavailable").foregroundStyle(.secondary) }
        case .file where Self.imageFile(c) != nil:
            if let img = NSImage(contentsOfFile: Self.imageFile(c)!) {
                Image(nsImage: img).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        default:
            PreviewText(text: c.text, mono: Self.looksLikeCode(c.text), id: c.id,
                        onSelect: { clip.previewSelection = $0 },
                        onReturn: { model.key(.enter) },
                        onEscape: { clip.previewSelection = ""; clip.focusTick += 1 })
        }
    }

    private func info(_ c: Clip) -> some View {
        let rows: [(String, AnyView)] = {
            var r: [(String, AnyView)] = [("Source", AnyView(SourceLabel(bundle: c.sourceBundle, name: c.sourceName)))]
            r.append(("Type", AnyView(Text(Self.typeName(c.kind)))))
            switch c.kind {
            case .image:
                r.append(("Dimensions", AnyView(Text("\(c.width)×\(c.height)"))))
                r.append(("Size", AnyView(Text(ByteCountFormatter.string(fromByteCount: Int64(c.bytes), countStyle: .file)))))
            default:
                r.append(("Characters", AnyView(Text("\(c.chars)"))))
                r.append(("Words", AnyView(Text("\(c.words > 0 ? c.words : c.text.split(whereSeparator: \.isWhitespace).count)"))))
            }
            r.append(("Copied", AnyView(Text(c.created, format: .dateTime.day().month().year().hour().minute().second()))))
            return r
        }()
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer()
                    row.1
                }
                .font(.system(size: 13))
                .padding(.horizontal, 10).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(i % 2 == 0 ? 0.05 : 0)))
            }
        }
    }

    /// Path of the copied file if it's a single image file (Finder copy), so it can be previewed.
    static func imageFile(_ c: Clip) -> String? {
        guard c.kind == .file, !c.text.contains("\n") else { return nil }
        let url = URL(fileURLWithPath: c.text)
        guard let t = UTType(filenameExtension: url.pathExtension), t.conforms(to: .image) else { return nil }
        return c.text
    }

    private static func typeName(_ k: ClipKind) -> String {
        switch k { case .text: return "Text"; case .url: return "Link"; case .image: return "Image"; case .file: return "File" }
    }

    private static func looksLikeCode(_ s: String) -> Bool {
        s.contains("\n") && s.contains(where: { "{}();=<>/\\#$".contains($0) })
    }
}

struct ClipRow: View {
    let clip: Clip
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 28, height: 28)
            Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1)
            Spacer(minLength: 0)
            if clip.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Color.white.opacity(0.09) : .clear))
        .contentShape(Rectangle())
    }

    private var title: String {
        switch clip.kind {
        case .image: return "Image (\(clip.width)×\(clip.height))"
        case .file:
            // file names, not full paths
            return clip.text.split(separator: "\n").map { URL(fileURLWithPath: String($0)).lastPathComponent }.joined(separator: ", ")
        default:
            let line = clip.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? clip.text
            return String(line.trimmingCharacters(in: .whitespaces).prefix(200))
        }
    }

    @ViewBuilder private var icon: some View {
        switch clip.kind {
        case .image:
            if let p = clip.imagePath, let img = NSImage(contentsOf: ClipboardService.thumbURL(URL(fileURLWithPath: p))) {
                Image(nsImage: img).resizable().scaledToFill().frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else { Image(systemName: "photo").font(.system(size: 18)).foregroundStyle(.secondary) }
        case .url: Image(systemName: "link").font(.system(size: 17)).foregroundStyle(.secondary)
        case .file:
            if let p = ClipboardView.imageFile(clip), let img = NSImage(contentsOfFile: p) {
                Image(nsImage: img).resizable().scaledToFill().frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else { Image(systemName: "doc").font(.system(size: 17)).foregroundStyle(.secondary) }
        case .text: Image(systemName: "doc.text").font(.system(size: 17)).foregroundStyle(.secondary)
        }
    }
}

struct SourceLabel: View {
    let bundle: String
    let name: String
    var body: some View {
        HStack(spacing: 6) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
            }
            Text(name.isEmpty ? "Unknown" : name)
        }
    }
}

// MARK: - selectable preview (partial paste)

final class PreviewTextView: NSTextView {
    var onReturn: () -> Void = {}
    var onEscape: () -> Void = {}
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn()
        case 53: onEscape()
        default: super.keyDown(with: event)
        }
    }
}

struct PreviewText: NSViewRepresentable {
    let text: String
    let mono: Bool
    let id: Int64
    let onSelect: (String) -> Void
    let onReturn: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = PreviewTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 0, height: 4)
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.delegate = context.coordinator
        let sv = NSScrollView()
        sv.drawsBackground = false
        sv.hasVerticalScroller = true
        sv.scrollerStyle = .overlay
        sv.documentView = tv
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? PreviewTextView else { return }
        context.coordinator.onSelect = onSelect
        tv.onReturn = onReturn
        tv.onEscape = onEscape
        if context.coordinator.shownID != id || tv.string != text {
            context.coordinator.shownID = id
            tv.font = mono ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13)
            tv.textColor = .labelColor
            tv.string = text
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            tv.scrollToBeginningOfDocument(nil)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelect: (String) -> Void = { _ in }
        var shownID: Int64 = -1
        func textViewDidChangeSelection(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            let r = tv.selectedRange()
            onSelect(r.length > 0 ? (tv.string as NSString).substring(with: r) : "")
        }
    }
}
