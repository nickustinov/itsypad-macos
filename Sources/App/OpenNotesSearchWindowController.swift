import Cocoa

final class OpenNotesSearchWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private let onSelect: (UUID) -> Void
    private let onClose: () -> Void
    private let allTabs: [TabData]
    private var filteredTabs: [TabData]

    private let searchField = NSSearchField()
    private let tableView = NSTableView()

    init(
        tabs: [TabData],
        onSelect: @escaping (UUID) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onSelect = onSelect
        self.onClose = onClose
        self.allTabs = tabs
        self.filteredTabs = tabs

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Search open notes..."
        window.level = .floating
        window.isFloatingPanel = true
        window.tabbingMode = .disallowed

        super.init(window: window)

        window.delegate = self
        buildInterface()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }
        contentView.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Search note name or contents"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchFieldDidChange(_:))
        searchField.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.title = "Note"
        column.width = 380
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.selectionHighlightStyle = .regular
        tableView.target = self
        tableView.doubleAction = #selector(activateSelectedTab)
        tableView.allowsMultipleSelection = false
        tableView.rowHeight = 22

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        contentView.addSubview(searchField)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])

        window?.makeFirstResponder(searchField)
        tableView.reloadData()
    }

    @objc private func searchFieldDidChange(_ sender: NSSearchField) {
        filteredTabs = OpenNotesSearchHelpers.filteredTabs(allTabs, query: sender.stringValue)
        tableView.reloadData()
    }

    @objc private func activateSelectedTab() {
        let selectedRow = tableView.selectedRow
        let row = selectedRow >= 0 ? selectedRow : 0
        guard row < filteredTabs.count else { return }
        onSelect(filteredTabs[row].id)
        onClose()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredTabs.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("OpenNoteCell")
        var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
        if cell == nil {
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail

            let cellView = NSTableCellView()
            cellView.identifier = identifier
            cellView.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
            cellView.textField = textField
            cell = cellView
        }

        if let tab = filteredTabs[safe: row] {
            cell?.textField?.stringValue = tab.name
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return row >= 0 && row < filteredTabs.count
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}
