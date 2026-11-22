import Cocoa

/// Spotlight-style global search content: a search field above a grouped results list.
/// Searches across all open tabs and reveals the chosen match in the editor.
final class GlobalSearchView: NSView, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {

    /// Called when the user activates a match (tab id + range in that tab's content).
    var onActivate: ((UUID, NSRange) -> Void)?
    /// Called when the user dismisses the overlay (Esc).
    var onClose: (() -> Void)?
    var onOpenFile: ((URL) -> Void)?
    /// Supplies the tabs to search. Injected so the view stays decoupled from TabStore.
    var tabsProvider: () -> [GlobalSearch.Source] = { [] }
    var folderRoot: URL?

    private enum Row {
        case header(GlobalSearchTabResult)
        case match(tabID: UUID, GlobalSearchMatch)
        case file(URL, String)
    }

    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "")

    private var rows: [Row] = []
    private var selectedRow: Int?
    private var folderFiles: [URL] = []
    private var folderLoading = false
    private var folderError = false
    private var folderLoadID = UUID()

    private static let headerRowID = NSUserInterfaceItemIdentifier("gsHeader")
    private static let matchRowID = NSUserInterfaceItemIdentifier("gsMatch")
    private static let headerHeight: CGFloat = 24
    private static let matchHeight: CGFloat = 24

    var isDark = false { didSet { applyTheme() } }
    var themeBackground: NSColor = .windowBackgroundColor { didSet { applyTheme() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = String(localized: "search.global.placeholder", defaultValue: "Search all tabs…")
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.font = NSFont.systemFont(ofSize: 15)
        searchField.focusRingType = .none
        searchField.delegate = self

        let divider = NSBox()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.boxType = .separator

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("gsColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(tableClicked)
        tableView.style = .plain

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = NSFont.systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        addSubview(searchField)
        addSubview(divider)
        addSubview(scrollView)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            searchField.heightAnchor.constraint(equalToConstant: 28),

            divider.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 24),
        ])

        reload()
    }

    /// Resets the field and results, then focuses the search field. Called on present.
    func prepareForDisplay() {
        searchField.stringValue = ""
        folderLoadID = UUID()
        folderFiles = []
        folderError = false
        folderLoading = folderRoot != nil
        searchField.placeholderString = folderRoot == nil
            ? String(localized: "search.global.placeholder", defaultValue: "Search all tabs…")
            : String(localized: "search.folder.placeholder", defaultValue: "Search folder files…")
        if let root = folderRoot {
            let loadID = folderLoadID
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = Result { try FolderFileSearch.files(in: root) }
                DispatchQueue.main.async {
                    guard let self, self.folderLoadID == loadID else { return }
                    self.folderLoading = false
                    switch result {
                    case .success(let files):
                        self.folderFiles = files
                    case .failure(let error):
                        NSLog("[FolderSearch] Failed to search folder: %@", error.localizedDescription)
                        self.folderError = true
                    }
                    self.reload()
                }
            }
        }
        reload()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self.searchField)
        }
    }

    @objc private func searchChanged() {
        reload()
    }

    private func reload() {
        let query = searchField.stringValue
        if let root = folderRoot {
            rows = FolderFileSearch.matches(query: query, files: folderFiles, root: root)
                .map { .file($0, FolderFileSearch.relativePath(of: $0, in: root)) }
        } else {
            let results = GlobalSearch.run(query: query, in: tabsProvider())
            rows = results.flatMap { result -> [Row] in
                [.header(result)] + result.matches.map { .match(tabID: result.tabID, $0) }
            }
        }

        tableView.reloadData()

        if folderLoading {
            emptyLabel.stringValue = String(localized: "search.folder.loading", defaultValue: "Loading files…")
            emptyLabel.isHidden = false
        } else if folderError {
            emptyLabel.stringValue = String(localized: "search.folder.error", defaultValue: "Could not search this folder")
            emptyLabel.isHidden = false
        } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptyLabel.stringValue = folderRoot == nil
                ? String(localized: "search.global.hint", defaultValue: "Search across all open tabs")
                : String(localized: "search.folder.hint", defaultValue: "Search files in the open folder")
            emptyLabel.isHidden = false
        } else if rows.isEmpty {
            emptyLabel.stringValue = String(localized: "search.global.no_matches", defaultValue: "No matches")
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }

        selectRow(firstSelectableRow())
    }

    // MARK: - Selection

    private func firstSelectableRow() -> Int? {
        rows.firstIndex { if case .header = $0 { return false } else { return true } }
    }

    private func nextSelectableRow(after row: Int?) -> Int? {
        let start = (row ?? -1) + 1
        guard start < rows.count else { return row }
        for i in start..<rows.count {
            if case .header = rows[i] { continue }
            return i
        }
        return row
    }

    private func previousSelectableRow(before row: Int?) -> Int? {
        guard let row, row > 0 else { return row }
        for i in stride(from: row - 1, through: 0, by: -1) {
            if case .header = rows[i] { continue }
            return i
        }
        return row
    }

    private func selectRow(_ index: Int?) {
        selectedRow = index
        if let index {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        } else {
            tableView.deselectAll(nil)
        }
    }

    private func activateRow(_ index: Int?) {
        guard let index, index < rows.count else { return }
        switch rows[index] {
        case .match(let tabID, let match): onActivate?(tabID, match.range)
        case .file(let url, _): onOpenFile?(url)
        case .header: break
        }
    }

    // MARK: - NSSearchFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            selectRow(nextSelectableRow(after: selectedRow))
            return true
        case #selector(NSResponder.moveUp(_:)):
            selectRow(previousSelectableRow(before: selectedRow))
            return true
        case #selector(NSResponder.insertNewline(_:)):
            activateRow(selectedRow)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }

    // MARK: - Table click

    @objc private func tableClicked() {
        let clicked = tableView.clickedRow
        guard clicked >= 0, clicked < rows.count else { return }
        switch rows[clicked] {
        case .header:
            break
        case .match, .file:
            selectRow(clicked)
            activateRow(clicked)
        }
        // Keep typing fluid: clicking a header shouldn't steal focus from the field.
        window?.makeFirstResponder(searchField)
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .header = rows[row] { return Self.headerHeight }
        return Self.matchHeight
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .header = rows[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        AlwaysEmphasizedRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let result):
            let view = (tableView.makeView(withIdentifier: Self.headerRowID, owner: self) as? GlobalSearchHeaderCell) ?? {
                let v = GlobalSearchHeaderCell()
                v.identifier = Self.headerRowID
                return v
            }()
            view.configure(name: result.tabName, count: result.matches.count)
            return view
        case .match(_, let match):
            let view = (tableView.makeView(withIdentifier: Self.matchRowID, owner: self) as? GlobalSearchMatchCell) ?? {
                let v = GlobalSearchMatchCell()
                v.identifier = Self.matchRowID
                return v
            }()
            view.configure(match: match)
            return view
        case .file(_, let path):
            let view = (tableView.makeView(withIdentifier: Self.matchRowID, owner: self) as? GlobalSearchMatchCell) ?? {
                let v = GlobalSearchMatchCell()
                v.identifier = Self.matchRowID
                return v
            }()
            view.configure(path: path)
            return view
        }
    }

    // MARK: - Theme

    private func applyTheme() {
        layer?.backgroundColor = themeBackground.cgColor
        appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}

/// Draws an accent-coloured selection even while the search field holds first responder,
/// so the highlighted result always reads as "current" (Spotlight-style).
private final class AlwaysEmphasizedRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set { }
    }
}

// MARK: - Header cell

private final class GlobalSearchHeaderCell: NSTableCellView {
    private let icon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.lineBreakMode = .byTruncatingTail

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.textColor = .tertiaryLabelColor

        addSubview(icon)
        addSubview(nameLabel)
        addSubview(countLabel)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(name: String, count: Int) {
        nameLabel.stringValue = name
        countLabel.stringValue = count == 1
            ? String(localized: "search.global.match_one", defaultValue: "1 match")
            : String(localized: "search.global.match_many", defaultValue: "\(count) matches")
    }
}

// MARK: - Match cell

private final class GlobalSearchMatchCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        addSubview(label)
        textField = label

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 29),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(match: GlobalSearchMatch) {
        // Only the font weight encodes the highlight (no colour), so it reads correctly
        // both normally and on the emphasized selection background.
        let attributed = NSMutableAttributedString(string: match.snippet)
        if match.highlightRange.location != NSNotFound,
           NSMaxRange(match.highlightRange) <= (match.snippet as NSString).length {
            attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 12, weight: .bold), range: match.highlightRange)
        }
        label.attributedStringValue = attributed
    }

    func configure(path: String) {
        label.stringValue = path
    }
}
