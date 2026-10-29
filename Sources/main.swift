// Ordock — app nella barra dei menu che mette in ordine le app del Dock:
// per nome, colore, ultimo utilizzo o categoria, con ordini salvati,
// pulizia, scorciatoia da tastiera, pannello impostazioni e ripristino dell'ordine originale.

import AppKit
import Carbon.HIToolbox
import CoreServices
import ServiceManagement
import SwiftUI

// MARK: - Lettura e scrittura del Dock

let dockDomain = "com.apple.dock" as CFString
let appsKey = "persistent-apps" as CFString

/// Una "casella" del Dock (un'app, oppure uno spazio vuoto).
struct Tile {
    let raw: [String: Any]

    /// Uno spazio vuoto piccolo, usato come separatore tra le categorie.
    static func spacer() -> Tile {
        Tile(raw: ["tile-type": "small-spacer-tile", "tile-data": [String: Any]()])
    }

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

    var bundleID: String? {
        tileData["bundle-identifier"] as? String ?? path.flatMap { Bundle(path: $0)?.bundleIdentifier }
    }

    /// false se l'app è stata cancellata dal Mac ma è rimasta nel Dock.
    var appExists: Bool {
        guard let path else { return true }
        return FileManager.default.fileExists(atPath: path)
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

    /// Rimette il Dock come in `saved`. Le app aggiunte dopo vanno in fondo.
    /// Con `addMissing` rimette anche le app tolte nel frattempo, se sono ancora sul Mac.
    static func arranged(like saved: [Tile], addMissing: Bool) -> [Tile] {
        let current = readTiles().filter { !$0.isSpacer }
        var free: [String: [Int]] = [:]
        for (i, t) in current.enumerated() { free[t.key, default: []].append(i) }

        var used = Set<Int>()
        var result: [Tile] = []
        var added = Set<String>()
        for t in saved {
            if t.isSpacer { result.append(t); continue }
            if let i = free[t.key]?.first {
                free[t.key]?.removeFirst()
                used.insert(i)
                result.append(current[i])
            } else if addMissing, t.path != nil, t.appExists, !added.contains(t.key) {
                added.insert(t.key)
                result.append(t)
            }
        }
        result += current.indices.filter { !used.contains($0) }.map { current[$0] }
        return result
    }
}

// MARK: - File dell'app (~/Library/Application Support/Ordock)

enum Storage {
    private static var base: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    static var folder: URL { base.appendingPathComponent("Ordock", isDirectory: true) }

    /// Porta con sé la copia di sicurezza della vecchia "Riordina Dock".
    static func migrateFromOldName() {
        let old = base.appendingPathComponent("Riordina Dock", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: old.path) && !fm.fileExists(atPath: folder.path) {
            try? fm.copyItem(at: old, to: folder)
        }
    }

    static func write(_ plist: Any, to name: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    static func read(_ name: String) -> Any? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
    }
}

// MARK: - Copia di sicurezza dell'ordine originale

enum Backup {
    static let orderFile = "ordine-originale.plist"
    static let fullCopyFile = "copia-completa-dock.plist"

    static var exists: Bool { Storage.exists(fullCopyFile) || Storage.exists(orderFile) }

    static func save(_ tiles: [Tile]) throws {
        try Storage.write(tiles.map { $0.key }, to: orderFile)
        try Storage.write(tiles.map { $0.raw }, to: fullCopyFile)
    }

    static func loadTiles() -> [Tile]? {
        (Storage.read(fullCopyFile) as? [[String: Any]])?.map { Tile(raw: $0) }
    }

    static func loadKeys() -> [String]? { Storage.read(orderFile) as? [String] }
}

// MARK: - Ordini salvati

struct SavedOrder {
    let name: String
    let tiles: [Tile]
}

enum SavedOrders {
    private static let file = "ordini-salvati.plist"

    static func all() -> [SavedOrder] {
        let list = Storage.read(file) as? [[String: Any]] ?? []
        return list.compactMap { entry in
            guard let name = entry["nome"] as? String,
                  let raw = entry["caselle"] as? [[String: Any]] else { return nil }
            return SavedOrder(name: name, tiles: raw.map { Tile(raw: $0) })
        }
    }

    private static func store(_ orders: [SavedOrder]) throws {
        try Storage.write(orders.map { ["nome": $0.name, "caselle": $0.tiles.map { $0.raw }] as [String: Any] }, to: file)
    }

    /// Salva (o sostituisce, se il nome esiste già) un ordine.
    static func save(_ name: String, _ tiles: [Tile]) throws {
        var orders = all().filter { $0.name != name }
        orders.append(SavedOrder(name: name, tiles: tiles))
        try store(orders)
    }

    static func delete(_ name: String) throws {
        try store(all().filter { $0.name != name })
    }
}

// MARK: - Ultimo utilizzo delle app

enum Usage {
    private static let storeKey = "ultimoUtilizzo"

    /// Percorso "pulito", così la stessa app combacia tra Dock e app in esecuzione.
    static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// Date registrate dall'app stessa ogni volta che porti un'app in primo piano.
    private static var recorded: [String: Date] {
        UserDefaults.standard.dictionary(forKey: storeKey) as? [String: Date] ?? [:]
    }

    static func record(_ app: NSRunningApplication) {
        guard let path = app.bundleURL?.path else { return }
        var all = recorded
        all[normalized(path)] = Date()
        UserDefaults.standard.set(all, forKey: storeKey)
    }

    /// Data di ultima apertura salvata da macOS (Spotlight).
    private static func spotlightDate(_ path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// La data più recente tra quella di macOS e quella registrata dall'app.
    static func lastUsed(_ tile: Tile) -> Date? {
        guard let path = tile.path else { return nil }
        let dates = [spotlightDate(path), recorded[normalized(path)]].compactMap { $0 }
        return dates.max()
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

// MARK: - Lingua (scelta dall'utente, oppure quella del Mac)

var isItalian: Bool {
    switch Prefs.language {
    case "it": return true
    case "en": return false
    default: return Locale.preferredLanguages.first?.lowercased().hasPrefix("it") ?? false
    }
}

func L(_ italian: String, _ english: String) -> String { isItalian ? italian : english }

// MARK: - Categorie

enum Categories {
    /// Categorie già pronte: chiave, nome italiano, nome inglese.
    static let builtIn: [(key: String, it: String, en: String)] = [
        ("browsing", "Browsing", "Browsing"),
        ("mail", "Mail", "Mail"),
        ("social", "Socials", "Socials"),
        ("grafica", "Grafica", "Design"),
        ("video", "Video", "Video"),
        ("musica", "Musica e audio", "Music & audio"),
        ("lavoro", "Lavoro", "Work"),
        ("sviluppo", "Sviluppo", "Development"),
        ("utility", "Utility", "Utilities"),
        ("svago", "Svago", "Fun"),
        ("sistema", "Sistema", "System"),
        ("altro", "Altro", "Other"),
    ]
    static let fallback = "altro"
    private static let customPrefix = "custom:"
    private static let orderKey = "ordineCategorie"
    private static let choicesKey = "categorieScelte"

    /// Le categorie nell'ordine in cui finiscono nel Dock (da sinistra).
    static var order: [String] {
        get { UserDefaults.standard.stringArray(forKey: orderKey) ?? builtIn.map { $0.key } }
        set { UserDefaults.standard.set(newValue, forKey: orderKey) }
    }

    static func isCustom(_ key: String) -> Bool { key.hasPrefix(customPrefix) }

    /// Simbolo di sistema (SF Symbols) per ogni categoria.
    static func symbol(_ key: String) -> String {
        let symbols = [
            "browsing": "globe", "mail": "envelope", "social": "bubble.left.and.bubble.right",
            "grafica": "paintbrush", "video": "film", "musica": "music.note", "lavoro": "briefcase",
            "sviluppo": "chevron.left.forwardslash.chevron.right", "utility": "wrench.and.screwdriver",
            "svago": "gamecontroller", "sistema": "gearshape.2", "altro": "square.dashed",
        ]
        return symbols[key] ?? "tag"
    }

    static func name(_ key: String) -> String {
        if let b = builtIn.first(where: { $0.key == key }) { return L(b.it, b.en) }
        return String(key.dropFirst(customPrefix.count))
    }

    /// Categorie scelte a mano dall'utente (app → categoria).
    private static var choices: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: choicesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: choicesKey) }
    }

    static func category(for tile: Tile) -> String {
        if let chosen = choices[tile.key], order.contains(chosen) { return chosen }
        let auto = automatic(for: tile)
        return order.contains(auto) ? auto : (order.contains(fallback) ? fallback : order.last ?? fallback)
    }

    static func choose(_ category: String, for tileKey: String) { choices[tileKey] = category }
    static func resetChoices() { choices = [:] }

    /// Crea una categoria nuova (in fondo, prima di "Altro") e restituisce la sua chiave.
    @discardableResult
    static func add(_ name: String) -> String {
        if let existing = order.first(where: { self.name($0).lowercased() == name.lowercased() }) { return existing }
        let key = customPrefix + name
        var list = order
        list.insert(key, at: list.firstIndex(of: fallback) ?? list.endIndex)
        order = list
        return key
    }

    static func remove(_ key: String) {
        order = order.filter { $0 != key }
        choices = choices.filter { $0.value != key }
    }

    /// Le categorie nell'ordine scelto: alfabetico (con "Altro" sempre in fondo) o personalizzato.
    static var displayOrder: [String] {
        guard Prefs.groupOrder == .alphabetical else { return order }
        let sorted = order.filter { $0 != fallback }
            .sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
        return order.contains(fallback) ? sorted + [fallback] : sorted
    }

    /// Trascinamento nel pannello: parte dall'ordine che vedi e diventa "personalizzato".
    static func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var list = displayOrder
        let moving = source.map { list[$0] }
        let target = destination - source.filter { $0 < destination }.count
        for i in source.sorted(by: >) { list.remove(at: i) }
        list.insert(contentsOf: moving, at: min(max(target, 0), list.count))
        order = list
        Prefs.groupOrder = .custom
    }

    // Riconoscimento automatico: prima le app più comuni, poi la categoria che lo sviluppatore
    // ha scritto dentro l'app (LSApplicationCategoryType).
    private static let known: [String: [String]] = [
        "browsing": ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "company.thebrowser.Browser",
                     "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
                     "app.zen-browser.zen", "com.kagi.kagimacOS", "company.thebrowser.dia"],
        "mail": ["com.apple.mail", "com.microsoft.Outlook", "com.readdle.smartemail-Mac", "com.readdle.SparkDesktop",
                 "it.bloop.airmail2", "org.mozilla.thunderbird", "com.mimestream.Mimestream", "com.canarymail.mac",
                 "com.superhuman.electron"],
        "social": ["net.whatsapp.WhatsApp", "desktop.WhatsApp", "ru.keepcoder.Telegram", "com.tdesktop.Telegram",
                   "com.apple.MobileSMS", "com.apple.FaceTime", "com.hnc.Discord", "com.facebook.archon",
                   "com.facebook.archon.developerID", "org.whispersystems.signal-desktop", "com.atebits.Tweetie2",
                   "maccatalyst.com.atebits.Tweetie2", "com.burbn.instagram", "com.zhiliaoapp.musically"],
        "grafica": ["com.adobe.Photoshop", "com.adobe.illustrator", "com.adobe.InDesign", "com.adobe.Lightroom",
                    "com.adobe.lightroomCC", "com.adobe.xd", "com.figma.Desktop", "com.bohemiancoding.sketch3",
                    "com.seriflabs.affinity", "com.pixelmatorteam.pixelmator", "com.canva.CanvaDesktop",
                    "com.apple.Photos", "com.adobe.Firefly", "com.maxon.cinema4d", "org.blenderfoundation.blender"],
        "video": ["com.apple.FinalCut", "com.apple.iMovieApp", "com.blackmagic-design.DaVinciResolve",
                  "com.lemon.lvoverseas", "com.adobe.PremierePro", "com.adobe.AfterEffects", "org.videolan.vlc",
                  "com.apple.QuickTimePlayerX", "com.apple.TV", "com.colliderli.iina", "com.obsproject.obs-studio",
                  "com.apple.Compressor", "com.apple.motionapp"],
        "musica": ["com.apple.Music", "com.spotify.client", "com.apple.logic10", "com.apple.GarageBand10",
                   "com.ableton.live", "com.image-line.flstudio", "com.apple.podcasts", "com.apple.MainStage3",
                   "com.tidal.desktop", "org.audacityteam.audacity", "com.adobe.Audition"],
        "lavoro": ["com.apple.iWork.Pages", "com.apple.iWork.Numbers", "com.apple.iWork.Keynote",
                   "com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint", "com.microsoft.onenote.mac",
                   "com.microsoft.teams", "com.microsoft.teams2", "us.zoom.xos", "com.tinyspeck.slackmacgap",
                   "notion.id", "com.apple.Notes", "com.apple.reminders", "com.apple.iCal", "com.apple.AddressBook",
                   "md.obsidian", "com.todoist.mac.Todoist", "com.culturedcode.ThingsMac",
                   "com.openai.chat", "com.apple.freeform"],
        "sviluppo": ["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
                     "com.apple.Terminal", "com.googlecode.iterm2", "com.github.GitHubClient", "com.jetbrains.",
                     "com.sublimetext.", "com.panic.Nova", "com.docker.docker", "dev.warp.Warp-Stable",
                     "com.postmanlabs.mac", "com.getflywheel.lightning.local", "com.panic.transmit",
                     "ch.sudo.cyberduck", "org.filezilla-project.filezilla"],
        "utility": ["com.apple.Preview", "com.apple.calculator", "com.apple.Passwords", "com.1password.",
                    "com.agilebits.onepassword", "com.awehunt.QSpace", "com.raycast.macos",
                    "com.runningwithcrayons.Alfred", "com.apple.ScreenSharing", "com.apple.Image_Capture",
                    "com.apple.TextEdit", "com.apple.archiveutility", "com.getdropbox.dropbox",
                    "com.google.drivefs", "com.apple.findmy"],
        "svago": ["com.valvesoftware.steam", "com.epicgames.launcher", "com.apple.games", "com.apple.Chess",
                  "com.netflix.Netflix", "com.apple.iBooksX", "com.apple.news"],
        "sistema": ["com.apple.systempreferences", "com.apple.AppStore", "com.apple.ActivityMonitor",
                    "com.apple.Console", "com.apple.DiskUtility", "com.apple.apps.launcher",
                    "com.apple.launchpad.launcher", "com.apple.Siri", "com.apple.finder", "com.apple.Automator",
                    "com.apple.shortcuts", "com.apple.Home"],
    ]

    private static let appStoreCategories: [String: String] = [
        "public.app-category.graphics-design": "grafica", "public.app-category.photography": "grafica",
        "public.app-category.video": "video", "public.app-category.music": "musica",
        "public.app-category.social-networking": "social", "public.app-category.productivity": "lavoro",
        "public.app-category.business": "lavoro", "public.app-category.finance": "lavoro",
        "public.app-category.developer-tools": "sviluppo", "public.app-category.utilities": "utility",
        "public.app-category.games": "svago", "public.app-category.entertainment": "svago",
        "public.app-category.news": "svago", "public.app-category.lifestyle": "svago",
        "public.app-category.education": "lavoro", "public.app-category.reference": "lavoro",
    ]

    static func automatic(for tile: Tile) -> String {
        if let id = tile.bundleID {
            for (category, ids) in known where ids.contains(where: { id == $0 || id.hasPrefix($0) }) {
                return category
            }
        }
        if let path = tile.path,
           let type = Bundle(path: path)?.infoDictionary?["LSApplicationCategoryType"] as? String {
            for (prefix, category) in appStoreCategories where type.hasPrefix(prefix) { return category }
        }
        return fallback
    }
}

// MARK: - Modi di ordinare

enum SortMethod: String {
    case name, color, recentLeft, recentRight, category, categoryFirst
}

enum GroupOrder: String {
    case alphabetical = "alfabetico", custom = "personalizzato"
}

enum Prefs {
    private static var d: UserDefaults { .standard }

    /// L'ultimo modo usato: è quello che ripete la scorciatoia.
    static var lastMethod: SortMethod {
        get { SortMethod(rawValue: d.string(forKey: "ultimoMetodo") ?? "") ?? .name }
        set { d.set(newValue.rawValue, forKey: "ultimoMetodo") }
    }

    /// La categoria da mettere all'inizio del Dock (ordine "per prima").
    static var firstCategory: String {
        get { d.string(forKey: "categoriaPerPrima") ?? "" }
        set { d.set(newValue, forKey: "categoriaPerPrima") }
    }

    static var groupOrder: GroupOrder {
        get { GroupOrder(rawValue: d.string(forKey: "ordineGruppi") ?? "") ?? .alphabetical }
        set { d.set(newValue.rawValue, forKey: "ordineGruppi") }
    }

    static var separators: Bool {
        get { d.object(forKey: "separatori") as? Bool ?? true }
        set { d.set(newValue, forKey: "separatori") }
    }

    /// "auto" (come il Mac), "it" o "en". L'installazione la imposta con `defaults write`.
    static var language: String {
        get { d.string(forKey: "lingua") ?? "auto" }
        set { d.set(newValue, forKey: "lingua") }
    }

    /// Lettera della scorciatoia ⌃⌥⌘ (vuota = nessuna scorciatoia).
    static var hotKey: String {
        get { d.string(forKey: "scorciatoia") ?? "O" }
        set { d.set(newValue, forKey: "scorciatoia") }
    }
}

enum Sorter {
    static func sorted(_ tiles: [Tile], by method: SortMethod) -> [Tile] {
        // Gli spazi vuoti servono solo come separatori tra categorie: negli altri ordini li tolgo.
        let apps = tiles.filter { !$0.isSpacer }
        switch method {
        case .name: return byName(apps)
        case .color: return byColor(apps)
        case .recentLeft: return byLastUsed(apps, recentOnLeft: true)
        case .recentRight: return byLastUsed(apps, recentOnLeft: false)
        case .category: return byCategory(apps)
        case .categoryFirst: return byCategory(apps, first: Prefs.firstCategory)
        }
    }

    static func byName(_ apps: [Tile]) -> [Tile] {
        apps.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    static func byColor(_ apps: [Tile]) -> [Tile] {
        let analyzed = apps.map { ($0, colorInfo(for: $0)) }
        let colored = analyzed.filter { !$0.1.isNeutral }
            .sorted { $0.1.rainbowPosition < $1.1.rainbowPosition }
        // Le icone grigie/bianche/nere vanno in fondo, dalla più chiara alla più scura
        let neutral = analyzed.filter { $0.1.isNeutral }
            .sorted { $0.1.brightness > $1.1.brightness }
        return (colored + neutral).map { $0.0 }
    }

    static func byLastUsed(_ apps: [Tile], recentOnLeft: Bool) -> [Tile] {
        let dated = apps.enumerated().map { ($0.element, $0.offset, Usage.lastUsed($0.element)) }
        // Dalla più recente alla meno recente; le app mai usate in fondo, nell'ordine attuale.
        var sorted = dated.sorted { a, b in
            switch (a.2, b.2) {
            case let (da?, db?) where da != db: return da > db
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.1 < b.1
            }
        }.map { $0.0 }
        if !recentOnLeft { sorted.reverse() }
        return sorted
    }

    /// Raggruppa per categoria (nell'ordine delle categorie), A → Z dentro ogni gruppo.
    /// Con `first`, quella categoria va all'inizio del Dock e le altre seguono nell'ordine scelto.
    static func byCategory(_ apps: [Tile], first: String? = nil) -> [Tile] {
        let groups = Dictionary(grouping: apps) { Categories.category(for: $0) }
        var keys = Categories.displayOrder
        if let first, let i = keys.firstIndex(of: first) {
            keys.remove(at: i)
            keys.insert(first, at: 0)
        }
        var result: [Tile] = []
        for key in keys {
            guard let group = groups[key], !group.isEmpty else { continue }
            if Prefs.separators && !result.isEmpty { result.append(.spacer()) }
            result += byName(group)
        }
        return result
    }
}

// MARK: - Scorciatoia da tastiera (⌃⌥⌘ + lettera, funziona in qualsiasi app)

private func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?,
                           _ data: UnsafeMutableRawPointer?) -> OSStatus {
    Task { @MainActor in HotKey.onPress?() }
    return noErr
}

@MainActor
enum HotKey {
    static let letters: [(letter: String, code: Int)] = [
        ("O", kVK_ANSI_O), ("D", kVK_ANSI_D), ("R", kVK_ANSI_R),
    ]
    static var onPress: (@MainActor () -> Void)?
    private static var ref: EventHotKeyRef?
    private static var handlerInstalled = false

    static func label(_ letter: String) -> String { "⌃⌥⌘ \(letter)" }

    /// Registra la scorciatoia. Restituisce false se un'altra app la usa già.
    static func register(_ letter: String) -> Bool {
        if let old = ref { UnregisterEventHotKey(old); ref = nil }
        guard let code = letters.first(where: { $0.letter == letter })?.code else { return true }
        if !handlerInstalled {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &type, nil, nil)
            handlerInstalled = true
        }
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(code), UInt32(cmdKey | optionKey | controlKey),
                                         EventHotKeyID(signature: OSType(0x4F52_444B), id: 1),
                                         GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr else { return false }
        ref = newRef
        return true
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - App nella barra dei menu

let signature = "Made With Love ❤️ by MattDanieli"
let donateURL = URL(string: "https://paypal.me/mattdanieli")!
let websiteURL = URL(string: "https://www.mattdanieli.it/apps/")!

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Storage.migrateFromOldName()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Ordock") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "Ordock"
            }
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        // Da qui in poi ricordo quando usi ogni app, per un ordine più preciso.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        HotKey.onPress = { [weak self] in self?.run(Prefs.lastMethod) }
        _ = HotKey.register(Prefs.hotKey)
    }

    @objc private func appActivated(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            Usage.record(app)
        }
    }

    // Il menu si ricostruisce ogni volta che lo apri, così è sempre aggiornato (anche nella lingua).
    // Le icone sono simboli di sistema (SF Symbols), come nei menu di macOS.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(header("Ordock"))
        menu.addItem(.separator())
        menu.addItem(item(L("Ordina per nome (A → Z)", "Sort by name (A → Z)"), #selector(sortByName), symbol: "textformat.abc"))
        menu.addItem(item(L("Ordina per colore", "Sort by color"), #selector(sortByColor), symbol: "paintpalette"))
        menu.addItem(parent(L("Ordina per ultimo utilizzo", "Sort by last used"), recentMenu(), symbol: "clock"))
        menu.addItem(parent(L("Ordina per categoria", "Sort by category"), categoryMenu(), symbol: "square.grid.2x2"))
        menu.addItem(.separator())
        menu.addItem(parent(L("Ordini salvati", "Saved orders"), savedMenu(), symbol: "bookmark"))
        menu.addItem(parent(L("Pulizia Dock", "Clean up Dock"), cleanupMenu(), symbol: "sparkles"))
        menu.addItem(.separator())
        let restore = item(L("Ripristina ordine originale", "Restore original order"), #selector(restoreOriginal),
                           symbol: "arrow.uturn.backward")
        restore.isEnabled = Backup.exists
        menu.addItem(restore)
        menu.addItem(item(L("Salva l'ordine attuale come originale…", "Save current order as original…"),
                          #selector(saveCurrentAsOriginal), symbol: "square.and.arrow.down"))
        menu.addItem(.separator())
        menu.addItem(item(L("Impostazioni…", "Settings…"), #selector(openSettings), key: ",", symbol: "gearshape"))
        menu.addItem(parent(L("Lingua", "Language"), languageMenu(), symbol: "globe"))
        menu.addItem(parent(L("Scorciatoia", "Shortcut"), hotKeyMenu(), symbol: "command"))
        let login = item(L("Apri all'avvio del Mac", "Open at login"), #selector(toggleLogin), symbol: "power")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item(L("Dona con PayPal", "Donate with PayPal"), #selector(openDonate), symbol: "heart"))
        menu.addItem(item(L("Informazioni su Ordock", "About Ordock"), #selector(showAbout), symbol: "info.circle"))
        menu.addItem(item(L("Esci", "Quit"), #selector(quit), key: "q", symbol: "xmark.circle"))
        menu.addItem(.separator())
        let sign = item(signature, #selector(openWebsite))
        sign.attributedTitle = NSAttributedString(string: signature, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        menu.addItem(sign)
    }

    // MARK: Sottomenu

    private func recentMenu() -> NSMenu {
        let m = submenu()
        m.addItem(item(L("Più recenti a sinistra", "Most recent on the left"), #selector(sortRecentLeft), symbol: "arrow.left.to.line"))
        m.addItem(item(L("Più recenti a destra", "Most recent on the right"), #selector(sortRecentRight), symbol: "arrow.right.to.line"))
        return m
    }

    // Clic su una categoria = quella va all'inizio del Dock (a sinistra), poi tutte le altre in ordine.
    private func categoryMenu() -> NSMenu {
        let m = submenu()
        let apps = Sorter.byName(Dock.readTiles().filter { !$0.isSpacer })
        let counts = Dictionary(grouping: apps) { Categories.category(for: $0) }.mapValues { $0.count }
        let firstNow = Prefs.lastMethod == .categoryFirst ? Prefs.firstCategory : nil

        m.addItem(disabled(L("Metti per prima nel Dock:", "Put first in the Dock:")))
        for key in Categories.displayOrder {
            guard let count = counts[key], count > 0 else { continue }
            let i = item("\(Categories.name(key))  ·  \(count)", #selector(putFirstItem(_:)),
                         symbol: Categories.symbol(key))
            i.representedObject = key
            i.state = key == firstNow ? .on : .off
            m.addItem(i)
        }
        m.addItem(.separator())
        let all = item(L("Tutte in ordine, nessuna per prima", "All in order, none first"), #selector(sortByCategory),
                       symbol: "arrow.up.arrow.down")
        all.state = Prefs.lastMethod == .category ? .on : .off
        m.addItem(all)
        m.addItem(.separator())

        // Cambia la categoria di un'app
        let appsMenu = submenu()
        for app in apps {
            let current = Categories.category(for: app)
            let choices = submenu()
            for key in Categories.displayOrder {
                let c = item(Categories.name(key), #selector(chooseCategoryItem(_:)), symbol: Categories.symbol(key))
                c.representedObject = [app.key, key]
                c.state = key == current ? .on : .off
                choices.addItem(c)
            }
            appsMenu.addItem(parent("\(app.label)  ·  \(Categories.name(current))", choices))
        }
        if apps.isEmpty { appsMenu.addItem(disabled(L("Nessuna app nel Dock", "No apps in the Dock"))) }
        m.addItem(parent(L("Cambia categoria a un'app", "Change an app's category"), appsMenu, symbol: "tag"))

        let orderMenu = submenu()
        let alpha = item(L("Alfabetico (A → Z)", "Alphabetical (A → Z)"), #selector(chooseGroupOrder(_:)))
        alpha.representedObject = GroupOrder.alphabetical.rawValue
        alpha.state = Prefs.groupOrder == .alphabetical ? .on : .off
        orderMenu.addItem(alpha)
        let custom = item(L("Personalizzato", "Custom"), #selector(chooseGroupOrder(_:)))
        custom.representedObject = GroupOrder.custom.rawValue
        custom.state = Prefs.groupOrder == .custom ? .on : .off
        orderMenu.addItem(custom)
        m.addItem(parent(L("Ordine delle altre categorie", "Order of the other categories"), orderMenu, symbol: "list.bullet"))

        let sep = item(L("Spazi tra una categoria e l'altra", "Spaces between categories"), #selector(toggleSeparators),
                       symbol: "rectangle.split.3x1")
        sep.state = Prefs.separators ? .on : .off
        m.addItem(sep)
        m.addItem(.separator())
        m.addItem(item(L("Gestisci categorie…", "Manage categories…"), #selector(manageCategories), symbol: "slider.horizontal.3"))
        return m
    }

    private func savedMenu() -> NSMenu {
        let m = submenu()
        let orders = SavedOrders.all()
        if orders.isEmpty {
            m.addItem(disabled(L("Nessun ordine salvato", "No saved orders")))
        }
        for o in orders {
            let i = item(o.name, #selector(applySavedItem(_:)), symbol: "bookmark.fill")
            i.representedObject = o.name
            m.addItem(i)
        }
        m.addItem(.separator())
        m.addItem(item(L("Salva l'ordine attuale…", "Save current order…"), #selector(saveOrderFromMenu), symbol: "plus"))
        if !orders.isEmpty {
            let del = submenu()
            for o in orders {
                let i = item(o.name, #selector(deleteSavedItem(_:)))
                i.representedObject = o.name
                del.addItem(i)
            }
            m.addItem(parent(L("Elimina", "Delete"), del, symbol: "trash"))
        }
        return m
    }

    private func cleanupMenu() -> NSMenu {
        let m = submenu()
        m.addItem(disabled(L("Trova le app non usate da…", "Find apps not used for…")))
        for months in cleanupChoices {
            let i = item(monthsLabel(months), #selector(cleanupItem(_:)), symbol: "calendar")
            i.representedObject = months
            m.addItem(i)
        }
        return m
    }

    private func languageMenu() -> NSMenu {
        let m = submenu()
        for (code, title) in [("auto", L("Automatica (come il Mac)", "Automatic (same as Mac)")),
                              ("it", "Italiano"), ("en", "English")] {
            let i = item(title, #selector(chooseLanguage(_:)))
            i.representedObject = code
            i.state = Prefs.language == code ? .on : .off
            m.addItem(i)
        }
        return m
    }

    private func hotKeyMenu() -> NSMenu {
        let m = submenu()
        m.addItem(disabled(L("Ripete l'ultimo ordine che hai usato", "Repeats the last sort you used")))
        m.addItem(.separator())
        let none = item(L("Nessuna", "None"), #selector(chooseHotKey(_:)))
        none.representedObject = ""
        none.state = Prefs.hotKey.isEmpty ? .on : .off
        m.addItem(none)
        for l in HotKey.letters {
            let i = item(HotKey.label(l.letter), #selector(chooseHotKey(_:)))
            i.representedObject = l.letter
            i.state = Prefs.hotKey == l.letter ? .on : .off
            m.addItem(i)
        }
        return m
    }

    let cleanupChoices = [1, 3, 6, 12]

    func monthsLabel(_ months: Int) -> String {
        switch months {
        case 1: return L("1 mese", "1 month")
        case 12: return L("1 anno", "1 year")
        default: return L("\(months) mesi", "\(months) months")
        }
    }

    // MARK: Pezzi del menu

    private func submenu() -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        return m
    }

    private func symbolImage(_ name: String?) -> NSImage? {
        guard let name, let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        image.isTemplate = true
        return image
    }

    private func item(_ title: String, _ action: Selector, key: String = "", symbol: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        i.image = symbolImage(symbol)
        return i
    }

    private func parent(_ title: String, _ sub: NSMenu, symbol: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = sub
        i.image = symbolImage(symbol)
        return i
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func header(_ title: String) -> NSMenuItem {
        let i = disabled(title)
        i.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        ])
        return i
    }

    // MARK: Azioni (usate sia dal menu sia dal pannello impostazioni)

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

    func run(_ method: SortMethod) {
        guard let tiles = prepare() else { return }
        Prefs.lastMethod = method
        Dock.write(Sorter.sorted(tiles, by: method))
    }

    @objc private func sortByName() { run(.name) }
    @objc private func sortByColor() { run(.color) }
    @objc private func sortRecentLeft() { run(.recentLeft) }
    @objc private func sortRecentRight() { run(.recentRight) }
    @objc private func sortByCategory() { run(.category) }

    @objc private func toggleSeparators() { Prefs.separators.toggle() }

    @objc private func chooseGroupOrder(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let order = GroupOrder(rawValue: raw) {
            Prefs.groupOrder = order
        }
    }

    @objc private func manageCategories() { showSettings(tab: .categories) }

    @objc private func putFirstItem(_ sender: NSMenuItem) {
        if let key = sender.representedObject as? String { putFirst(key) }
    }

    /// Ordina per categoria mettendo `key` all'inizio del Dock.
    func putFirst(_ key: String) {
        Prefs.firstCategory = key
        run(.categoryFirst)
    }

    @objc private func chooseCategoryItem(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        Categories.choose(pair[1], for: pair[0])
    }

    func deleteCategory(_ key: String) {
        guard confirm(L("Eliminare la categoria \"\(Categories.name(key))\"?", "Delete the \"\(Categories.name(key))\" category?"),
                      L("Le sue app tornano nella loro categoria automatica.", "Its apps go back to their automatic category."),
                      ok: L("Elimina", "Delete")) else { return }
        Categories.remove(key)
    }

    @objc func resetCategories() {
        guard confirm(L("Tornare alle categorie automatiche?", "Go back to automatic categories?"),
                      L("Le scelte fatte a mano per ogni app vengono cancellate. Le categorie create da te restano.",
                        "The choices you made for each app are cleared. Categories you created are kept."),
                      ok: L("Conferma", "Confirm")) else { return }
        Categories.resetChoices()
    }

    @objc private func saveOrderFromMenu() {
        guard let name = ask(L("Salva l'ordine attuale", "Save current order"),
                             L("Dai un nome a questo ordine, così lo richiami con un clic.",
                               "Name this order so you can bring it back with one click."),
                             placeholder: L("Es. Lavoro", "E.g. Work"), ok: L("Salva", "Save"))
        else { return }
        saveOrder(named: name)
    }

    func saveOrder(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if SavedOrders.all().contains(where: { $0.name == name }),
           !confirm(L("\"\(name)\" esiste già", "\"\(name)\" already exists"),
                    L("Vuoi sostituirlo con l'ordine di adesso?", "Replace it with the current order?"),
                    ok: L("Sostituisci", "Replace")) { return }
        do { try SavedOrders.save(name, Dock.readTiles()) } catch {
            alert(L("Salvataggio non riuscito", "Save failed"), error.localizedDescription)
        }
    }

    @objc private func applySavedItem(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { applySaved(named: name) }
    }

    func applySaved(named name: String) {
        guard let order = SavedOrders.all().first(where: { $0.name == name }),
              prepare() != nil else { return }
        Dock.write(Dock.arranged(like: order.tiles, addMissing: true))
    }

    @objc private func deleteSavedItem(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { deleteSaved(named: name) }
    }

    func deleteSaved(named name: String) {
        guard confirm(L("Eliminare \"\(name)\"?", "Delete \"\(name)\"?"),
                      L("Il Dock non cambia: sparisce solo l'ordine salvato.", "The Dock doesn't change: only the saved order is removed."),
                      ok: L("Elimina", "Delete")) else { return }
        try? SavedOrders.delete(name)
    }

    @objc private func cleanupItem(_ sender: NSMenuItem) {
        if let months = sender.representedObject as? Int { cleanup(months: months) }
    }

    func cleanup(months: Int) {
        guard let limit = Calendar.current.date(byAdding: .month, value: -months, to: Date()) else { return }
        let format = DateFormatter()
        format.dateStyle = .medium

        // App da proporre: cancellate dal Mac, non usate da tempo, o mai aperte (queste non spuntate).
        var found: [(tile: Tile, reason: String, checked: Bool)] = []
        for t in Dock.readTiles() where !t.isSpacer {
            if !t.appExists {
                found.append((t, L("non è più sul Mac", "no longer on this Mac"), true))
            } else if let date = Usage.lastUsed(t) {
                if date < limit { found.append((t, L("ultimo uso: ", "last used: ") + format.string(from: date), true)) }
            } else {
                found.append((t, L("mai aperta o data sconosciuta", "never opened or date unknown"), false))
            }
        }
        guard !found.isEmpty else {
            alert(L("Tutto in ordine ✨", "All tidy ✨"),
                  L("Nel Dock non ci sono app inutilizzate da così tanto tempo.", "There are no apps in the Dock unused for that long."))
            return
        }

        let rowHeight: CGFloat = 24, width: CGFloat = 400
        let list = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: rowHeight * CGFloat(found.count)))
        let boxes = found.enumerated().map { i, f -> NSButton in
            let b = NSButton(checkboxWithTitle: "\(f.tile.label)  —  \(f.reason)", target: nil, action: nil)
            b.state = f.checked ? .on : .off
            b.frame = NSRect(x: 0, y: CGFloat(i) * rowHeight, width: width, height: rowHeight)
            list.addSubview(b)
            return b
        }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width + 20, height: min(list.frame.height, 300)))
        scroll.documentView = list
        scroll.hasVerticalScroller = list.frame.height > 300
        scroll.drawsBackground = false

        let a = makeAlert(L("Quali app vuoi togliere dal Dock?", "Which apps do you want to remove from the Dock?"),
                          L("Le app restano sul Mac, spariscono solo dal Dock. Prima salvo l'ordine di adesso in \"Ordini salvati\", così puoi tornare indietro.",
                            "The apps stay on your Mac, they only leave the Dock. First I save the current order in \"Saved orders\", so you can go back."))
        a.accessoryView = scroll
        a.addButton(withTitle: L("Togli dal Dock", "Remove from Dock"))
        a.addButton(withTitle: L("Annulla", "Cancel"))
        guard a.runModal() == .alertFirstButtonReturn else { return }

        let remove = Set(zip(found, boxes).filter { $0.1.state == .on }.map { $0.0.tile.key })
        guard !remove.isEmpty, let tiles = prepare() else { return }
        let stamp = DateFormatter()
        stamp.dateFormat = "d MMM yyyy HH:mm"
        do { try SavedOrders.save(L("Prima della pulizia", "Before clean-up") + " · " + stamp.string(from: Date()), tiles) } catch {
            alert(L("Non riesco a salvare la copia di sicurezza", "Can't save the backup"),
                  L("Per sicurezza non modifico il Dock.", "To be safe, the Dock was not changed.") + "\n\n\(error.localizedDescription)")
            return
        }
        Dock.write(tiles.filter { !remove.contains($0.key) })
    }

    @objc private func chooseHotKey(_ sender: NSMenuItem) {
        if let letter = sender.representedObject as? String { _ = setHotKey(letter) }
    }

    /// Cambia la scorciatoia. Restituisce false se un'altra app la usa già.
    func setHotKey(_ letter: String) -> Bool {
        if HotKey.register(letter) {
            Prefs.hotKey = letter
            return true
        }
        _ = HotKey.register(Prefs.hotKey)
        alert(L("Scorciatoia già in uso", "Shortcut already in use"),
              L("\(HotKey.label(letter)) è usata da un'altra app. Prova un'altra lettera.",
                "\(HotKey.label(letter)) is used by another app. Try another letter."))
        return false
    }

    @objc private func chooseLanguage(_ sender: NSMenuItem) {
        if let code = sender.representedObject as? String {
            Prefs.language = code
            languageChanged()
        }
    }

    func languageChanged() {
        settingsWindow?.title = L("Ordock · Impostazioni", "Ordock · Settings")
    }

    @objc func restoreOriginal() {
        if let saved = Backup.loadTiles() {
            Dock.write(Dock.arranged(like: saved, addMissing: false))
            return
        }
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

    @objc func saveCurrentAsOriginal() {
        guard confirm(L("Salvare l'ordine attuale come originale?", "Save the current order as the original?"),
                      L("D'ora in poi \"Ripristina\" riporterà il Dock com'è adesso. L'ordine salvato prima verrà sostituito.",
                        "From now on \"Restore\" will bring the Dock back to how it is now. The previously saved order will be replaced."),
                      ok: L("Salva", "Save")) else { return }
        do { try Backup.save(Dock.readTiles()) } catch {
            alert(L("Salvataggio non riuscito", "Save failed"), error.localizedDescription)
        }
    }

    @objc func toggleLogin() {
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

    @objc func openSettings() { showSettings(tab: nil) }

    func showSettings(tab: PanelTab?) {
        if let tab { UserDefaults.standard.set(tab.rawValue, forKey: "schedaImpostazioni") }
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(app: self)))
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        languageChanged()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func openDonate() { NSWorkspace.shared.open(donateURL) }
    @objc func openWebsite() { NSWorkspace.shared.open(websiteURL) }

    @objc private func showAbout() {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let credits = NSMutableAttributedString(string: signature + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: center,
        ])
        credits.append(NSAttributedString(string: L("Ti piace Ordock? Offrimi un caffè: ", "Like Ordock? Buy me a coffee: "), attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: center,
        ]))
        credits.append(NSAttributedString(string: "paypal.me/mattdanieli", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .link: donateURL, .paragraphStyle: center,
        ]))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Ordock", .credits: credits])
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Finestre di dialogo (tutte con la firma in fondo)

    private func makeAlert(_ title: String, _ text: String) -> NSAlert {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text + "\n\n" + signature
        return a
    }

    private func alert(_ title: String, _ text: String) {
        makeAlert(title, text).runModal()
    }

    private func confirm(_ title: String, _ text: String, ok: String) -> Bool {
        let a = makeAlert(title, text)
        a.addButton(withTitle: ok)
        a.addButton(withTitle: L("Annulla", "Cancel"))
        return a.runModal() == .alertFirstButtonReturn
    }

    /// Chiede un nome; restituisce nil se annulli o lasci vuoto.
    private func ask(_ title: String, _ text: String, placeholder: String, ok: String) -> String? {
        let a = makeAlert(title, text)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = placeholder
        a.accessoryView = field
        a.addButton(withTitle: ok)
        a.addButton(withTitle: L("Annulla", "Cancel"))
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

// MARK: - Pannello impostazioni

enum PanelTab: Int {
    case general, sort, categories, saved, cleanup
}

struct SettingsView: View {
    let app: AppDelegate
    @AppStorage("lingua") private var language = "auto"
    @AppStorage("schedaImpostazioni") private var tab = PanelTab.general.rawValue
    @State private var tick = 0

    var body: some View {
        let refresh = { tick += 1 }
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                GeneralTab(app: app)
                    .tabItem { Label(L("Generale", "General"), systemImage: "gearshape") }
                    .tag(PanelTab.general.rawValue)
                SortTab(app: app)
                    .tabItem { Label(L("Ordina", "Sort"), systemImage: "arrow.up.arrow.down") }
                    .tag(PanelTab.sort.rawValue)
                CategoriesTab(app: app, refresh: refresh)
                    .tabItem { Label(L("Categorie", "Categories"), systemImage: "square.grid.2x2") }
                    .tag(PanelTab.categories.rawValue)
                SavedTab(app: app, refresh: refresh)
                    .tabItem { Label(L("Ordini salvati", "Saved orders"), systemImage: "bookmark") }
                    .tag(PanelTab.saved.rawValue)
                CleanupTab(app: app, refresh: refresh)
                    .tabItem { Label(L("Pulizia e ripristino", "Clean-up & restore"), systemImage: "sparkles") }
                    .tag(PanelTab.cleanup.rawValue)
            }
            // Cambiando lingua (o dopo una modifica) il pannello si ridisegna da capo.
            .id("\(language)-\(tick)")
            .padding(16)
            Divider()
            HStack {
                Button(signature) { app.openWebsite() }
                    .buttonStyle(.link)
                    .font(.footnote)
                Spacer()
                Button { app.openDonate() } label: {
                    Label(L("Dona con PayPal", "Donate with PayPal"), systemImage: "heart.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 680, height: 580)
        .onChange(of: language) { _ in app.languageChanged() }
    }
}

struct GeneralTab: View {
    let app: AppDelegate
    @AppStorage("lingua") private var language = "auto"
    @AppStorage("scorciatoia") private var hotKey = "O"
    @State private var login = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Picker(selection: $language) {
                    Text(L("Automatica (come il Mac)", "Automatic (same as Mac)")).tag("auto")
                    Text("Italiano").tag("it")
                    Text("English").tag("en")
                } label: {
                    Label(L("Lingua", "Language"), systemImage: "globe")
                }
                Toggle(isOn: Binding(
                    get: { login },
                    set: { _ in
                        app.toggleLogin()
                        login = SMAppService.mainApp.status == .enabled
                    })) {
                    Label(L("Apri all'avvio del Mac", "Open at login"), systemImage: "power")
                }
            }
            Section {
                Picker(selection: Binding(
                    get: { hotKey },
                    set: { newValue in _ = app.setHotKey(newValue) })) {
                    Text(L("Nessuna", "None")).tag("")
                    ForEach(HotKey.letters.map { $0.letter }, id: \.self) { letter in
                        Text(HotKey.label(letter)).tag(letter)
                    }
                } label: {
                    Label(L("Scorciatoia da tastiera", "Keyboard shortcut"), systemImage: "command")
                }
                Text(L("Ripete l'ultimo ordine che hai usato, da qualsiasi app.",
                       "Repeats the last sort you used, from any app."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct SortTab: View {
    let app: AppDelegate

    var body: some View {
        Form {
            Section(L("Ordina adesso", "Sort now")) {
                sortButton(L("Per nome (A → Z)", "By name (A → Z)"), "textformat.abc", .name)
                sortButton(L("Per colore", "By color"), "paintpalette", .color)
                sortButton(L("Per ultimo utilizzo, più recenti a sinistra", "By last used, most recent on the left"),
                           "arrow.left.to.line", .recentLeft)
                sortButton(L("Per ultimo utilizzo, più recenti a destra", "By last used, most recent on the right"),
                           "arrow.right.to.line", .recentRight)
                sortButton(L("Per categoria", "By category"), "square.grid.2x2", .category)
            }
            Section {
                Text(L("Quando riordini, il Dock sparisce e riappare per un secondo: è normale.",
                       "The Dock disappears and reappears for a second when sorting: that's normal."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func sortButton(_ title: String, _ symbol: String, _ method: SortMethod) -> some View {
        Button { app.run(method) } label: { Label(title, systemImage: symbol) }
    }
}

/// Gestione delle categorie: a sinistra i gruppi, a destra le app del gruppo scelto.
struct CategoriesTab: View {
    let app: AppDelegate
    let refresh: () -> Void
    @AppStorage("ordineGruppi") private var groupOrder = GroupOrder.alphabetical.rawValue
    @AppStorage("separatori") private var separators = true
    @AppStorage("categoriaScelta") private var selected = "browsing"
    @State private var newName = ""

    var body: some View {
        let apps = Sorter.byName(Dock.readTiles().filter { !$0.isSpacer })
        let order = Categories.displayOrder
        let current = order.contains(selected) ? selected : (order.first ?? Categories.fallback)
        let inGroup = apps.filter { Categories.category(for: $0) == current }
        let others = apps.filter { Categories.category(for: $0) != current }

        VStack(alignment: .leading, spacing: 12) {
            // Opzioni dell'ordine dei gruppi
            HStack(spacing: 16) {
                Picker(L("Ordine dei gruppi", "Group order"), selection: $groupOrder) {
                    Text(L("Alfabetico (A → Z)", "Alphabetical (A → Z)")).tag(GroupOrder.alphabetical.rawValue)
                    Text(L("Personalizzato", "Custom")).tag(GroupOrder.custom.rawValue)
                }
                .pickerStyle(.segmented)
                .frame(width: 380)
                Toggle(L("Spazi tra i gruppi", "Spaces between groups"), isOn: $separators)
            }

            HStack(alignment: .top, spacing: 16) {
                // Gruppi
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Gruppi da sinistra · trascinali per riordinare", "Groups from the left · drag to reorder"))
                        .font(.caption).foregroundStyle(.secondary)
                    List(selection: Binding<String?>(get: { current }, set: { if let s = $0 { selected = s } })) {
                        ForEach(order, id: \.self) { key in
                            HStack {
                                Label(Categories.name(key), systemImage: Categories.symbol(key))
                                Spacer()
                                Text("\(apps.filter { Categories.category(for: $0) == key }.count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .tag(key)
                        }
                        .onMove { from, to in
                            // Trascinare passa da solo all'ordine personalizzato.
                            Categories.move(fromOffsets: from, toOffset: to)
                            refresh()
                        }
                    }
                    HStack {
                        TextField(L("Nuovo gruppo", "New group"), text: $newName)
                            .onSubmit(addGroup)
                        Button(action: addGroup) { Image(systemName: "plus") }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button {
                            app.deleteCategory(current)
                            refresh()
                        } label: { Image(systemName: "minus") }
                            .disabled(!Categories.isCustom(current))
                            .help(L("Si possono eliminare solo i gruppi creati da te",
                                    "Only groups you created can be deleted"))
                    }
                }
                .frame(width: 240)

                // App del gruppo scelto
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("App in \"\(Categories.name(current))\"", "Apps in \"\(Categories.name(current))\""))
                        .font(.caption).foregroundStyle(.secondary)
                    List {
                        if inGroup.isEmpty {
                            Text(L("Nessuna app. Aggiungine una qui sotto.", "No apps. Add one below."))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(inGroup, id: \.key) { tile in
                            HStack {
                                AppIcon(tile: tile)
                                Text(tile.label).lineLimit(1)
                                Spacer()
                                Menu(L("Sposta in", "Move to")) {
                                    ForEach(order.filter { $0 != current }, id: \.self) { key in
                                        Button(Categories.name(key)) {
                                            Categories.choose(key, for: tile.key)
                                            refresh()
                                        }
                                    }
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                        }
                    }
                    HStack {
                        Menu {
                            ForEach(others, id: \.key) { tile in
                                Button("\(tile.label)  ·  \(Categories.name(Categories.category(for: tile)))") {
                                    Categories.choose(current, for: tile.key)
                                    refresh()
                                }
                            }
                        } label: {
                            Label(L("Aggiungi app a questo gruppo", "Add an app to this group"), systemImage: "plus.circle")
                        }
                        .fixedSize()
                        .disabled(others.isEmpty)
                        Spacer()
                        Button(L("Categorie automatiche", "Automatic categories")) {
                            app.resetCategories()
                            refresh()
                        }
                        .help(L("Annulla le scelte fatte a mano", "Clears the choices you made by hand"))
                    }
                }
            }

            HStack {
                Button { app.putFirst(current) } label: {
                    Label(L("Metti \"\(Categories.name(current))\" per prima nel Dock", "Put \"\(Categories.name(current))\" first in the Dock"),
                          systemImage: Categories.symbol(current))
                }
                .buttonStyle(.borderedProminent)
                Button { app.run(.category) } label: {
                    Label(L("Tutte in ordine", "All in order"), systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    private func addGroup() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        selected = Categories.add(name)
        newName = ""
        refresh()
    }
}

struct AppIcon: View {
    let tile: Tile

    var body: some View {
        Image(nsImage: tile.path.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSImage())
            .resizable()
            .frame(width: 20, height: 20)
    }
}

struct SavedTab: View {
    let app: AppDelegate
    let refresh: () -> Void
    @State private var name = ""

    var body: some View {
        let orders = SavedOrders.all()
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Salva il Dock com'è adesso e richiamalo con un clic.",
                   "Save the Dock as it is now and bring it back with one click."))
                .foregroundStyle(.secondary)
            if orders.isEmpty {
                Text(L("Nessun ordine salvato", "No saved orders"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.secondary)
            } else {
                List(orders, id: \.name) { order in
                    HStack {
                        Image(systemName: "bookmark.fill").foregroundStyle(.secondary)
                        Text(order.name).lineLimit(1)
                        Text("· \(order.tiles.filter { !$0.isSpacer }.count) app").foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Applica", "Apply")) { app.applySaved(named: order.name) }
                        Button { app.deleteSaved(named: order.name); refresh() } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            HStack {
                TextField(L("Nome, es. Lavoro", "Name, e.g. Work"), text: $name)
                Button {
                    app.saveOrder(named: name)
                    name = ""
                    refresh()
                } label: {
                    Label(L("Salva ordine attuale", "Save current order"), systemImage: "plus")
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct CleanupTab: View {
    let app: AppDelegate
    let refresh: () -> Void
    @AppStorage("mesiPulizia") private var months = 3

    var body: some View {
        Form {
            Section(L("Pulizia Dock", "Clean up Dock")) {
                Picker(L("Trova le app non usate da", "Find apps not used for"), selection: $months) {
                    ForEach(app.cleanupChoices, id: \.self) { m in Text(app.monthsLabel(m)).tag(m) }
                }
                Button { app.cleanup(months: months) } label: {
                    Label(L("Cerca app da togliere…", "Find apps to remove…"), systemImage: "sparkles")
                }
                Text(L("Le app restano sul Mac: spariscono solo dal Dock.", "Apps stay on your Mac: they only leave the Dock."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Ripristino", "Restore")) {
                Button { app.restoreOriginal() } label: {
                    Label(L("Ripristina ordine originale", "Restore original order"), systemImage: "arrow.uturn.backward")
                }
                .disabled(!Backup.exists)
                Button {
                    app.saveCurrentAsOriginal()
                    refresh()
                } label: {
                    Label(L("Salva l'ordine attuale come originale…", "Save current order as original…"),
                          systemImage: "square.and.arrow.down")
                }
                Button {
                    try? FileManager.default.createDirectory(at: Storage.folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(Storage.folder)
                } label: {
                    Label(L("Apri la cartella delle copie di sicurezza", "Open the backup folder"), systemImage: "folder")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Avvio

@main
@MainActor
enum OrdockApp {
    static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
