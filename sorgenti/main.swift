// Riordina Dock — app nella barra dei menu che ordina le app del Dock
// per nome o per colore, con ripristino dell'ordine originale.

import AppKit
import ServiceManagement

// MARK: - Lettura e scrittura del Dock

let dockDomain = "com.apple.dock" as CFString
let appsKey = "persistent-apps" as CFString

/// Una "casella" del Dock (un'app, oppure uno spazio vuoto).
struct Tile {
    let raw: [String: Any]

    var tileData: [String: Any] { raw["tile-data"] as? [String: Any] ?? [:] }
    var type: String { raw["tile-type"] as? String ?? "" }
    var isSpacer: Bool { type.contains("spacer") }
    var label: String { tileData["file-label"] as? String ?? "" }

    var urlString: String {
        (tileData["file-data"] as? [String: Any])?["_CFURLString"] as? String ?? ""
    }

    /// Identificativo stabile, usato per ricordare l'ordine.
    var key: String {
        if !urlString.isEmpty { return urlString }
        if let guid = raw["GUID"] { return "GUID:\(guid)" }
        return "LABEL:\(label)"
    }

    /// Percorso dell'app sul disco (serve per leggere la sua icona).
    var path: String? {
        if let url = URL(string: urlString), url.isFileURL { return url.path }
        if urlString.hasPrefix("/") { return urlString }
        return nil
    }
}

enum Dock {
    static func readTiles() -> [Tile] {
        CFPreferencesAppSynchronize(dockDomain)
        guard let value = CFPreferencesCopyAppValue(appsKey, dockDomain) as? [[String: Any]] else {
            return []
        }
        return value.map { Tile(raw: $0) }
    }

    @discardableResult
    static func write(_ tiles: [Tile]) -> Bool {
        let array = tiles.map { $0.raw } as NSArray
        CFPreferencesSetAppValue(appsKey, array, dockDomain)
        let ok = CFPreferencesAppSynchronize(dockDomain)
        restart()
        return ok
    }

    static func restart() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
        process.waitUntilExit()
    }
}

// MARK: - Copia di sicurezza dell'ordine originale

enum Backup {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Riordina Dock", isDirectory: true)
    }
    static var orderFile: URL { folder.appendingPathComponent("ordine-originale.plist") }
    static var fullCopyFile: URL { folder.appendingPathComponent("copia-completa-dock.plist") }

    static var exists: Bool { FileManager.default.fileExists(atPath: orderFile.path) }

    static func save(_ tiles: [Tile]) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let keys = tiles.map { $0.key }
        let keysData = try PropertyListSerialization.data(fromPropertyList: keys, format: .xml, options: 0)
        try keysData.write(to: orderFile, options: .atomic)
        // Copia completa di emergenza (con tutti i dati originali del Dock)
        let full = tiles.map { $0.raw }
        if let fullData = try? PropertyListSerialization.data(fromPropertyList: full, format: .xml, options: 0) {
            try? fullData.write(to: fullCopyFile, options: .atomic)
        }
    }

    static func loadKeys() -> [String]? {
        guard let data = try? Data(contentsOf: orderFile),
              let keys = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String]
        else { return nil }
        return keys
    }
}

// MARK: - Analisi del colore delle icone

struct ColorInfo {
    let isNeutral: Bool    // grigio / bianco / nero
    let hue: Double        // 0...1
    let brightness: Double // 0...1

    /// Posizione nell'arcobaleno: rossi → arancioni → gialli → verdi → blu → viola → rosa
    var rainbowPosition: Double { hue >= 0.94 ? hue - 1 : hue }
}

func colorInfo(for tile: Tile) -> ColorInfo {
    guard let path = tile.path else { return ColorInfo(isNeutral: true, hue: 0, brightness: 0.5) }

    let icon = NSWorkspace.shared.icon(forFile: path)
    let size = 48
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return ColorInfo(isNeutral: true, hue: 0, brightness: 0.5) }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
              from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    let binCount = 24
    var bins = [Double](repeating: 0, count: binCount)
    var visible = 0.0, colored = 0.0, brightnessSum = 0.0

    for x in 0..<size {
        for y in 0..<size {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  c.alphaComponent > 0.5 else { continue }
            let h = Double(c.hueComponent)
            let s = Double(c.saturationComponent)
            let b = Double(c.brightnessComponent)
            visible += 1
            brightnessSum += b
            if s > 0.25 && b > 0.2 {
                colored += 1
                let bin = min(binCount - 1, Int(h * Double(binCount)))
                bins[bin] += s * b
            }
        }
    }

    let avgBrightness = visible > 0 ? brightnessSum / visible : 0.5
    if visible == 0 || colored / visible < 0.15 {
        return ColorInfo(isNeutral: true, hue: 0, brightness: avgBrightness)
    }

    // Colore dominante: la fascia di tinta più "pesante" (contando le vicine)
    var bestBin = 0, bestScore = -1.0
    for i in 0..<binCount {
        let score = bins[i] + 0.5 * bins[(i + 1) % binCount] + 0.5 * bins[(i + binCount - 1) % binCount]
        if score > bestScore { bestScore = score; bestBin = i }
    }
    // Media precisa dentro la fascia scelta e le due vicine
    var sx = 0.0, sy = 0.0
    for offset in -1...1 {
        let i = (bestBin + offset + binCount) % binCount
        let center = (Double(i) + 0.5) / Double(binCount)
        sx += cos(center * 2 * .pi) * bins[i]
        sy += sin(center * 2 * .pi) * bins[i]
    }
    var hue = atan2(sy, sx) / (2 * .pi)
    if hue < 0 { hue += 1 }
    return ColorInfo(isNeutral: false, hue: hue, brightness: avgBrightness)
}

// MARK: - Lingua (italiano se il Mac è in italiano, altrimenti inglese)

let isItalian = Locale.preferredLanguages.first?.lowercased().hasPrefix("it") ?? false
func L(_ italian: String, _ english: String) -> String { isItalian ? italian : english }

// MARK: - App nella barra dei menu

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let restoreItem = NSMenuItem(title: L("↩️  Ripristina ordine originale", "↩️  Restore original order"),
                                         action: #selector(AppDelegate.restoreOriginal), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: L("Apri all'avvio del Mac", "Open at login"),
                                       action: #selector(AppDelegate.toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Riordina Dock") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "Dock"
            }
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(header("Riordina Dock"))
        menu.addItem(.separator())
        menu.addItem(item(L("🔤  Ordina per nome (A → Z)", "🔤  Sort by name (A → Z)"), #selector(sortByName)))
        menu.addItem(item(L("🌈  Ordina per colore", "🌈  Sort by color"), #selector(sortByColor)))
        menu.addItem(.separator())
        restoreItem.target = self
        menu.addItem(restoreItem)
        menu.addItem(item(L("💾  Salva l'ordine attuale come originale…", "💾  Save current order as original…"), #selector(saveCurrentAsOriginal)))
        menu.addItem(.separator())
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(item(L("Esci", "Quit"), #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    // Aggiorna lo stato delle voci ogni volta che il menu si apre
    func menuWillOpen(_ menu: NSMenu) {
        restoreItem.isEnabled = Backup.exists
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func header(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        ])
        i.isEnabled = false
        return i
    }

    // MARK: Azioni

    /// Legge il Dock e, la prima volta, salva l'ordine originale.
    private func prepare() -> [Tile]? {
        let tiles = Dock.readTiles()
        guard !tiles.isEmpty else {
            alert(L("Non riesco a leggere il Dock", "Can't read the Dock"),
                  L("Non ho trovato app fisse nel Dock, oppure macOS non mi ha permesso di leggerle.",
                    "No pinned apps were found in the Dock, or macOS didn't allow reading them."))
            return nil
        }
        if !Backup.exists {
            do { try Backup.save(tiles) } catch {
                alert(L("Non riesco a salvare la copia di sicurezza", "Can't save the backup"),
                      L("Per sicurezza non modifico il Dock.", "To be safe, the Dock was not changed.") + "\n\n\(error.localizedDescription)")
                return nil
            }
        }
        return tiles
    }

    @objc private func sortByName() {
        guard let tiles = prepare() else { return }
        let apps = tiles.filter { !$0.isSpacer }
        let spacers = tiles.filter { $0.isSpacer }
        let sorted = apps.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        Dock.write(sorted + spacers)
    }

    @objc private func sortByColor() {
        guard let tiles = prepare() else { return }
        let apps = tiles.filter { !$0.isSpacer }
        let spacers = tiles.filter { $0.isSpacer }
        let analyzed = apps.map { ($0, colorInfo(for: $0)) }

        let colored = analyzed.filter { !$0.1.isNeutral }
            .sorted { $0.1.rainbowPosition < $1.1.rainbowPosition }
        // Le icone grigie/bianche/nere vanno in fondo, dalla più chiara alla più scura
        let neutral = analyzed.filter { $0.1.isNeutral }
            .sorted { $0.1.brightness > $1.1.brightness }

        Dock.write((colored + neutral).map { $0.0 } + spacers)
    }

    @objc private func restoreOriginal() {
        guard let keys = Backup.loadKeys() else {
            alert(L("Nessun ordine originale salvato", "No original order saved"),
                  L("Non c'è ancora niente da ripristinare.", "There is nothing to restore yet."))
            return
        }
        let current = Dock.readTiles()
        guard !current.isEmpty else { return }
        var position: [String: Int] = [:]
        for (i, k) in keys.enumerated() where position[k] == nil { position[k] = i }

        // Le app salvate tornano al loro posto; quelle aggiunte dopo vanno in fondo.
        let restored = current.enumerated().sorted { a, b in
            let pa = position[a.element.key] ?? Int.max
            let pb = position[b.element.key] ?? Int.max
            return pa != pb ? pa < pb : a.offset < b.offset
        }.map { $0.element }
        Dock.write(restored)
    }

    @objc private func saveCurrentAsOriginal() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = L("Salvare l'ordine attuale come originale?", "Save the current order as the original?")
        a.informativeText = L("D'ora in poi \"Ripristina\" riporterà il Dock com'è adesso. L'ordine salvato prima verrà sostituito.",
                              "From now on \"Restore\" will bring the Dock back to how it is now. The previously saved order will be replaced.")
        a.addButton(withTitle: L("Salva", "Save"))
        a.addButton(withTitle: L("Annulla", "Cancel"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do { try Backup.save(Dock.readTiles()) } catch {
            alert(L("Salvataggio non riuscito", "Save failed"), error.localizedDescription)
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert(L("Non riesco a cambiare l'apertura all'avvio", "Can't change the login setting"),
                  L("Puoi farlo a mano da Impostazioni di Sistema → Generali → Elementi login.",
                    "You can do it manually in System Settings → General → Login Items.") + "\n\n\(error.localizedDescription)")
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

// MARK: - Avvio

@main
@MainActor
enum RiordinaDockApp {
    static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
