import AppKit
import Vision
import NexusCore

struct TOTPEditor {
    var id: Int64?
    var name = ""
    /// Base32 secret or an `otpauth://` URI. Blank when editing = keep the stored secret.
    var secret = ""
    var algorithm = TOTPAlgorithm.sha1
    var digits = 6
    var period = 30
    var error: String?

    /// New entry using the defaults from Settings → 2FA.
    static func fresh() -> TOTPEditor {
        let d = Settings.shared.data
        return TOTPEditor(algorithm: TOTPAlgorithm(rawValue: d.totpAlgorithm) ?? .sha1, digits: d.totpDigits, period: d.totpPeriod)
    }
}

final class TOTPModel: ObservableObject {
    @Published var query = "" { didSet { selection = 0; reload() } }
    @Published private(set) var items: [TOTPEntry] = []
    @Published var selection = 0
    @Published var editor: TOTPEditor?
    @Published var focusTick = 0
    @Published var notice: String?
    var targetApp: NSRunningApplication?
    var dismiss: () -> Void = {}

    /// Decoded secrets, loaded while the module is open so codes can refresh every second without
    /// hitting the Keychain; dropped when the overlay closes.
    private var secrets: [Int64: [UInt8]] = [:]
    private var loading = Set<Int64>()

    let store: TOTPStore = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nexus")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return TOTPStore(path: dir.appendingPathComponent("totp.db").path)
    }()

    var selected: TOTPEntry? { items.indices.contains(selection) ? items[selection] : nil }
    var targetName: String { targetApp?.localizedName ?? "Frontmost App" }
    let primaryLabel = "Copy Code"

    func open() {
        query = ""
        selection = 0
        editor = nil
        notice = nil
        reload()
        focusTick += 1
    }

    func clearSecrets() { secrets.removeAll() }

    func reload() {
        items = store.all(query: query)
        // Keychain reads can be slow or block on a system prompt, so never on the main thread: rows show
        // placeholders until their secret arrives.
        let missing = items.map(\.id).filter { secrets[$0] == nil && !loading.contains($0) }
        loading.formUnion(missing)
        for id in missing {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let secret = SecretVault.get(id, service: SecretVault.totp).flatMap(TOTP.base32Decode)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.loading.remove(id)
                    if let secret { self.secrets[id] = secret; self.objectWillChange.send() }
                }
            }
        }
        if selection >= items.count { selection = max(0, items.count - 1) }
    }

    func move(_ d: Int) {
        guard !items.isEmpty else { return }
        selection = (selection + d + items.count) % items.count
    }

    func code(for e: TOTPEntry, at date: Date = Date()) -> String? {
        guard let s = secrets[e.id] else { return nil }
        return TOTP.code(secret: s, at: date, period: e.period, digits: e.digits, algorithm: e.algorithm)
    }

    // MARK: copy / paste

    func copy() { put(paste: false) }
    func paste() { put(paste: true) }

    private func put(paste: Bool) {
        guard let e = selected, code(for: e) != nil else { return }
        let target = targetApp
        let finish = { [self] in
            // regenerate: the auth prompt may have taken long enough for the window to roll over
            guard let c = code(for: e) else { return }
            dismiss()
            target?.activate()
            ClipboardService.shared.write(paste: paste, clearAfter: TimeInterval(Settings.shared.data.totpClearSeconds)) {
                $0.setString(c, forType: .string)
            }
        }
        if Settings.shared.data.totpRequireAuthToCopy {
            Task { @MainActor in if await Auth.verify(reason: "Use the 2FA code for “\(e.name)”") { finish() } }
        } else { finish() }
    }

    // MARK: editing

    func beginNew(prefill: TOTPEditor = .fresh()) {
        editor = prefill
        focusTick += 1
    }

    func beginEdit() {
        guard let e = selected else { return }
        Task { @MainActor in
            guard await Auth.verify(reason: "Edit the 2FA entry “\(e.name)”") else { return }
            editor = TOTPEditor(id: e.id, name: e.name, secret: "", algorithm: e.algorithm, digits: e.digits, period: e.period)
            focusTick += 1
        }
    }

    func deleteSelected() {
        guard let e = selected else { return }
        Task { @MainActor in
            guard await Auth.verify(reason: "Delete the 2FA entry “\(e.name)”") else { return }
            store.delete(e.id)
            SecretVault.delete(e.id, service: SecretVault.totp)
            secrets[e.id] = nil
            reload()
        }
    }

    func saveEditor() {
        guard var e = editor else { return }
        var name = e.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var algorithm = e.algorithm, digits = e.digits, period = e.period
        var secret = e.secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if secret.lowercased().hasPrefix("otpauth://") {
            guard let u = TOTP.parse(uri: secret) else { e.error = "Not a valid otpauth:// link."; editor = e; return }
            secret = u.secret; algorithm = u.algorithm; digits = u.digits; period = u.period
            if name.isEmpty { name = u.name }
        }
        guard !name.isEmpty else { e.error = "Name is required."; editor = e; return }
        if e.id == nil || !secret.isEmpty {
            guard TOTP.base32Decode(secret) != nil else { e.error = "Secret must be base32 (A–Z, 2–7) or an otpauth:// link."; editor = e; return }
        }
        let id: Int64
        if let existing = e.id {
            store.update(existing, name: name, algorithm: algorithm, digits: digits, period: period)
            id = existing
        } else {
            id = store.insert(name: name, algorithm: algorithm, digits: digits, period: period)
        }
        if !secret.isEmpty {
            guard SecretVault.set(secret.uppercased().filter { $0 != " " && $0 != "-" }, for: id, service: SecretVault.totp) else {
                if e.id == nil { store.delete(id) }
                e.error = "Couldn't save to the Keychain."; editor = e; return
            }
            secrets[id] = nil // reload from Keychain
        }
        editor = nil
        reload()
        if let i = items.firstIndex(where: { $0.id == id }) { selection = i }
        focusTick += 1
    }

    func cancelEditor() { editor = nil; focusTick += 1 }

    /// Reads a QR code from an image on the clipboard (e.g. a screenshot of the provider's setup page).
    func importFromClipboardQR() {
        let pb = NSPasteboard.general
        guard let data = pb.data(forType: .png) ?? pb.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: data), let cg = rep.cgImage else {
            notice = "Copy a screenshot of the QR code first."
            return
        }
        let req = VNDetectBarcodesRequest()
        req.symbologies = [.qr]
        try? VNImageRequestHandler(cgImage: cg).perform([req])
        let payloads = (req.results ?? []).compactMap(\.payloadStringValue)
        guard let uri = payloads.first(where: { $0.lowercased().hasPrefix("otpauth://") }), let u = TOTP.parse(uri: uri) else {
            notice = payloads.isEmpty ? "No QR code found in the clipboard image." : "That QR code isn't an otpauth:// 2FA code."
            return
        }
        notice = nil
        beginNew(prefill: TOTPEditor(name: u.name, secret: uri, algorithm: u.algorithm, digits: u.digits, period: u.period))
    }

    var actions: [ActionItem] {
        var a: [ActionItem] = []
        if selected != nil {
            a.append(ActionItem(title: primaryLabel, symbol: "doc.on.doc", run: { [self] in copy() }))
            a.append(ActionItem(title: "Paste Code to \(targetName)", symbol: "arrow.right.doc.on.clipboard", run: { [self] in paste() }))
        }
        a.append(ActionItem(title: "New Entry", symbol: "plus", keepsOpen: true, run: { [self] in beginNew() }))
        a.append(ActionItem(title: "Import QR from Clipboard", symbol: "qrcode.viewfinder", keepsOpen: true, run: { [self] in importFromClipboardQR() }))
        if selected != nil {
            a.append(ActionItem(title: "Edit… (needs login)", symbol: "pencil", keepsOpen: true, run: { [self] in beginEdit() }))
            a.append(ActionItem(title: "Delete… (needs login)", symbol: "trash", destructive: true, keepsOpen: true, run: { [self] in deleteSelected() }))
        }
        return a
    }
}
