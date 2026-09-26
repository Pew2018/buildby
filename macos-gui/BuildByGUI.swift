import Cocoa

struct AppInfo {
    let name: String
    let path: String
    let stack: String
    let detail: String
}

final class Scanner {
    private let fm = FileManager.default

    func scan() -> [AppInfo] {
        var paths = ["/Applications"]
        if let home = fm.homeDirectoryForCurrentUser.path.removingPercentEncoding {
            paths.append(home + "/Applications")
        }

        var results: [AppInfo] = []
        var seen = Set<String>()

        for root in paths {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in items where item.hasSuffix(".app") {
                let path = (root as NSString).appendingPathComponent(item)
                guard seen.insert(path).inserted else { continue }
                results.append(analyze(path: path))
            }
        }

        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func exists(_ app: String, _ relative: String) -> Bool {
        fm.fileExists(atPath: (app as NSString).appendingPathComponent(relative))
    }

    private func directoryContains(_ app: String, _ relative: String, prefix: String? = nil, suffix: String? = nil) -> Bool {
        let dir = (app as NSString).appendingPathComponent(relative)
        guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return false }
        return items.contains { item in
            if let prefix, !item.hasPrefix(prefix) { return false }
            if let suffix, !item.hasSuffix(suffix) { return false }
            return true
        }
    }

    private func analyze(path: String) -> AppInfo {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent

        if exists(path, "Contents/Frameworks/Electron Framework.framework") || exists(path, "Contents/Resources/app.asar") {
            return AppInfo(name: name, path: path, stack: "Electron", detail: "Electron / Chromium + Node.js")
        }
        if exists(path, "Contents/Frameworks/FlutterMacOS.framework") || exists(path, "Contents/Frameworks/App.framework/flutter_assets") {
            return AppInfo(name: name, path: path, stack: "Flutter", detail: "Flutter")
        }
        if exists(path, "Contents/Frameworks/Chromium Embedded Framework.framework") {
            return AppInfo(name: name, path: path, stack: "CEF", detail: "Chromium Embedded Framework")
        }
        if directoryContains(path, "Contents/Frameworks", prefix: "Qt", suffix: ".framework") {
            return AppInfo(name: name, path: path, stack: "Qt", detail: "Qt")
        }
        if exists(path, "Contents/Frameworks/nwjs Framework.framework") || exists(path, "Contents/Resources/app.nw") {
            return AppInfo(name: name, path: path, stack: "NW.js", detail: "NW.js")
        }
        if exists(path, "Contents/Frameworks/React.framework") {
            return AppInfo(name: name, path: path, stack: "React Native", detail: "React Native")
        }
        if exists(path, "Contents/Frameworks/Python.framework") || exists(path, "Contents/Resources/__boot__.py") || exists(path, "Contents/Resources/base_library.zip") {
            return AppInfo(name: name, path: path, stack: "Python", detail: "Python / py2app / PyInstaller")
        }
        if exists(path, "Contents/runtime/Contents/Home/lib/server/libjvm.dylib") || directoryContains(path, "Contents/Java", suffix: ".jar") {
            return AppInfo(name: name, path: path, stack: "JVM", detail: "Java / Kotlin")
        }
        if directoryContains(path, "Contents/Frameworks", prefix: "libgtk", suffix: ".dylib") {
            return AppInfo(name: name, path: path, stack: "GTK", detail: "GTK")
        }
        if directoryContains(path, "Contents/Frameworks", prefix: "libwx", suffix: ".dylib") {
            return AppInfo(name: name, path: path, stack: "wxWidgets", detail: "wxWidgets")
        }

        return AppInfo(name: name, path: path, stack: "Native / Other", detail: "No known cross-platform framework signature found")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private var window: NSWindow!
    private var tableView: NSTableView!
    private var statusLabel: NSTextField!
    private var filterField: NSSearchField!
    private var allApps: [AppInfo] = []
    private var shownApps: [AppInfo] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildUI()
        rescan()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildUI() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BuildBy"
        window.center()
        window.minSize = NSSize(width: 620, height: 400)

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let title = NSTextField(labelWithString: "Installed Apps")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        filterField = NSSearchField()
        filterField.placeholderString = "Filter by app or framework"
        filterField.target = self
        filterField.action = #selector(filterChanged)

        let refresh = NSButton(title: "Rescan", target: self, action: #selector(rescanAction))
        refresh.bezelStyle = .rounded

        statusLabel = NSTextField(labelWithString: "Scanning…")
        statusLabel.textColor = .secondaryLabelColor

        tableView = NSTableView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowSizeStyle = .medium
        tableView.delegate = self
        tableView.dataSource = self

        let appColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        appColumn.title = "Application"
        appColumn.width = 260
        let stackColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("stack"))
        stackColumn.title = "Built with"
        stackColumn.width = 190
        let pathColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        pathColumn.title = "Path"
        pathColumn.width = 340
        tableView.addTableColumn(appColumn)
        tableView.addTableColumn(stackColumn)
        tableView.addTableColumn(pathColumn)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder

        for v in [title, filterField, refresh, statusLabel, scroll] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),

            refresh.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            refresh.centerYAnchor.constraint(equalTo: title.centerYAnchor),

            filterField.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            filterField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            filterField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            statusLabel.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),

            scroll.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])

        window.makeKeyAndOrderFront(nil)
    }

    @objc private func rescanAction() { rescan() }

    private func rescan() {
        statusLabel.stringValue = "Scanning installed applications…"
        filterField.isEnabled = false

        DispatchQueue.global(qos: .userInitiated).async {
            let apps = Scanner().scan()
            DispatchQueue.main.async {
                self.allApps = apps
                self.filterField.isEnabled = true
                self.applyFilter()
            }
        }
    }

    @objc private func filterChanged() { applyFilter() }

    private func applyFilter() {
        let q = filterField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        shownApps = q.isEmpty ? allApps : allApps.filter {
            $0.name.lowercased().contains(q) || $0.stack.lowercased().contains(q) || $0.path.lowercased().contains(q)
        }

        let cross = shownApps.filter { $0.stack != "Native / Other" }.count
        statusLabel.stringValue = "\(shownApps.count) apps · \(cross) recognized cross-platform"
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shownApps.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app = shownApps[row]
        let value: String
        switch tableColumn?.identifier.rawValue {
        case "app": value = app.name
        case "stack": value = app.stack
        default: value = app.path
        }

        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        if cell.textField == nil {
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        cell.textField?.stringValue = value
        cell.textField?.toolTip = tableColumn?.identifier.rawValue == "stack" ? app.detail : value
        return cell
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
