import Cocoa

private let cardCellID = NSUserInterfaceItemIdentifier("ClipboardCard")
private let tileMinWidth: CGFloat = 200
private let tileHeight: CGFloat = 110
private let tileSpacing: CGFloat = 8
private let sectionInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

// MARK: - Clipboard card view

private class ClipboardCardView: NSView {
    private let previewLabel = NSTextField(wrappingLabelWithString: "")
    private let imageView = NSImageView()
    private let timestampLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private let copiedBadge = NSTextField(labelWithString: "Copied")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { updateBackground(); updateHoverControls() } }
    private var entry: ClipboardEntry?
    private var copiedFlashWork: DispatchWorkItem?
    var onDelete: ((UUID) -> Void)?

    var themeBackground: NSColor = .windowBackgroundColor { didSet { updateBackground() } }
    var isDark: Bool = false { didSet { updateAppearance() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6

        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.maximumNumberOfLines = 5
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        previewLabel.isSelectable = false
        previewLabel.cell?.truncatesLastVisibleLine = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.isHidden = true

        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.font = NSFont.systemFont(ofSize: 10)
        timestampLabel.textColor = .secondaryLabelColor
        timestampLabel.isSelectable = false
        timestampLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.bezelStyle = .inline
        deleteButton.isBordered = false
        let smallConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")?.withSymbolConfiguration(smallConfig)
        deleteButton.imagePosition = .imageOnly
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        deleteButton.isHidden = true
        deleteButton.contentTintColor = .secondaryLabelColor

        copiedBadge.translatesAutoresizingMaskIntoConstraints = false
        copiedBadge.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        copiedBadge.textColor = .secondaryLabelColor
        copiedBadge.isSelectable = false
        copiedBadge.isHidden = true

        addSubview(imageView)
        addSubview(previewLabel)
        addSubview(timestampLabel)
        addSubview(deleteButton)
        addSubview(copiedBadge)

        NSLayoutConstraint.activate([
            previewLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            previewLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            previewLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            previewLabel.bottomAnchor.constraint(lessThanOrEqualTo: timestampLabel.topAnchor, constant: -4),

            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            imageView.bottomAnchor.constraint(equalTo: timestampLabel.topAnchor, constant: -2),

            timestampLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            timestampLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            deleteButton.leadingAnchor.constraint(greaterThanOrEqualTo: timestampLabel.trailingAnchor, constant: 4),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            deleteButton.centerYAnchor.constraint(equalTo: timestampLabel.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 12),
            deleteButton.heightAnchor.constraint(equalToConstant: 12),

            copiedBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            copiedBadge.centerYAnchor.constraint(equalTo: timestampLabel.centerYAnchor),
        ])
    }

    private func updateHoverControls() {
        let showingCopied = !copiedBadge.isHidden
        deleteButton.isHidden = !isHovered || showingCopied
    }

    @objc private func deleteClicked() {
        guard let entry else { return }
        onDelete?(entry.id)
    }

    func configure(with entry: ClipboardEntry, searchQuery: String = "") {
        self.entry = entry

        switch entry.kind {
        case .text:
            imageView.isHidden = true
            previewLabel.isHidden = false
            configureTextPreview(text: entry.text ?? "", searchQuery: searchQuery)

        case .image:
            previewLabel.isHidden = true
            imageView.isHidden = false
            imageView.image = nil
            if let fileName = entry.imageFileName {
                let fileURL = ClipboardStore.shared.imagesDirectory.appendingPathComponent(fileName)
                imageView.image = NSImage(contentsOf: fileURL)
            }
        }

        timestampLabel.stringValue = relativeTime(from: entry.timestamp)
        updateBackground()
    }

    private func configureTextPreview(text: String, searchQuery: String) {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let textColor: NSColor = isDark ? .white : .black

        let lines = text.prefix(2000).components(separatedBy: .newlines)
        let trimmed = lines.map { String($0.drop(while: { $0 == " " || $0 == "\t" })) }

        if searchQuery.isEmpty {
            previewLabel.font = font
            previewLabel.attributedStringValue = NSAttributedString(
                string: trimmed.joined(separator: "\n"),
                attributes: [.font: font, .foregroundColor: textColor]
            )
            return
        }

        // Find the first match line to decide which portion to show
        let fullText = trimmed.joined(separator: "\n")
        let nsText = fullText as NSString
        let matchRange = nsText.range(of: searchQuery, options: .caseInsensitive)

        var displayText = fullText
        if matchRange.location != NSNotFound {
            // Find which line the match starts on
            let beforeMatch = nsText.substring(to: matchRange.location)
            let matchLine = beforeMatch.components(separatedBy: "\n").count - 1

            // If match is beyond line 2, offset the preview to show it
            if matchLine > 2, trimmed.count > 5 {
                let startLine = max(0, matchLine - 1)
                displayText = trimmed[startLine...].joined(separator: "\n")
            }
        }

        // Build attributed string with highlights
        let attributed = NSMutableAttributedString(
            string: displayText,
            attributes: [.font: font, .foregroundColor: textColor]
        )
        let highlightColor = NSColor.selectedTextBackgroundColor
        let nsDisplay = displayText as NSString
        var searchStart = 0
        while searchStart < nsDisplay.length {
            let range = nsDisplay.range(
                of: searchQuery,
                options: .caseInsensitive,
                range: NSRange(location: searchStart, length: nsDisplay.length - searchStart)
            )
            if range.location == NSNotFound { break }
            attributed.addAttribute(.backgroundColor, value: highlightColor, range: range)
            searchStart = range.location + range.length
        }

        previewLabel.attributedStringValue = attributed
    }

    func resetState() {
        copiedFlashWork?.cancel()
        copiedBadge.isHidden = true
        deleteButton.isHidden = true
        isHovered = false
        imageView.image = nil
        imageView.isHidden = true
        previewLabel.isHidden = false
    }

    private func updateAppearance() {
        previewLabel.textColor = isDark ? .white : .black
        timestampLabel.textColor = isDark
            ? NSColor.white.withAlphaComponent(0.5)
            : NSColor.black.withAlphaComponent(0.5)
        updateBackground()
    }

    private func updateBackground() {
        let blend: NSColor = isDark ? .white : .black
        let fraction: CGFloat = isDark ? (isHovered ? 0.12 : 0.07) : (isHovered ? 0.20 : 0.15)
        let cardBg = themeBackground.blended(withFraction: fraction, of: blend) ?? themeBackground
        layer?.backgroundColor = cardBg.cgColor
    }

    @objc private func cardClicked() {
        guard let entry else { return }
        ClipboardStore.shared.copyToClipboard(entry)
        showCopiedFlash()
    }

    private func showCopiedFlash() {
        copiedFlashWork?.cancel()

        copiedBadge.isHidden = false
        deleteButton.isHidden = true

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.copiedBadge.isHidden = true
            self.updateHoverControls()
        }
        copiedFlashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(ta)
        trackingArea = ta

        // Re-check mouse position on scroll to fix stale hover state
        if let window {
            let mouseInWindow = window.mouseLocationOutsideOfEventStream
            let localPoint = convert(mouseInWindow, from: nil)
            let mouseInside = visibleRect.contains(localPoint)
            if isHovered != mouseInside {
                isHovered = mouseInside
            }
        }
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDown(with event: NSEvent) {
        cardClicked()
    }

    private func relativeTime(from date: Date) -> String {
        let interval = -date.timeIntervalSinceNow
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        let days = Int(interval / 86400)
        if days == 1 { return "yesterday" }
        return "\(days)d ago"
    }
}

// MARK: - Collection view item

private class ClipboardCardItem: NSCollectionViewItem {
    override func loadView() {
        view = ClipboardCardView(frame: .zero)
    }

    var cardView: ClipboardCardView? { view as? ClipboardCardView }

    override func prepareForReuse() {
        super.prepareForReuse()
        cardView?.resetState()
    }
}

// MARK: - Clipboard content view

class ClipboardContentView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var filteredEntries: [ClipboardEntry] = []
    private var clipboardObserver: Any?
    private var tabSelectedObserver: Any?
    private var lastLayoutWidth: CGFloat = 0
    private var currentSearchQuery: String = ""

    var themeBackground: NSColor = .windowBackgroundColor {
        didSet { applyTheme() }
    }
    var isDark: Bool = false {
        didSet { applyTheme() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true

        // Search field
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search clipboard..."
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.font = NSFont.systemFont(ofSize: 12)

        // Flow layout
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = tileSpacing
        layout.minimumLineSpacing = tileSpacing
        layout.sectionInset = sectionInsets

        // Collection view
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ClipboardCardItem.self, forItemWithIdentifier: cardCellID)
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false

        // Scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        // Empty label
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = NSFont.systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isHidden = true

        addSubview(searchField)
        addSubview(scrollView)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            searchField.heightAnchor.constraint(equalToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 24),
        ])

        clipboardObserver = NotificationCenter.default.addObserver(
            forName: ClipboardStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadEntries()
        }

        tabSelectedObserver = NotificationCenter.default.addObserver(
            forName: ClipboardStore.clipboardTabSelectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.focusSearchField()
        }

        reloadEntries()
    }

    deinit {
        if let observer = clipboardObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = tabSelectedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func focusSearchField() {
        // Use afterDelay to ensure SwiftUI has finished its layout pass
        window?.perform(#selector(NSWindow.makeFirstResponder(_:)), with: searchField, afterDelay: 0.1)
    }

    override func layout() {
        super.layout()
        let width = scrollView.bounds.width
        if width != lastLayoutWidth {
            lastLayoutWidth = width
            collectionView.collectionViewLayout?.invalidateLayout()
        }
    }

    @objc private func searchChanged() {
        reloadEntries()
    }

    func reloadEntries() {
        let query = searchField.stringValue
        currentSearchQuery = query
        filteredEntries = ClipboardStore.shared.search(query: query)

        let isEmpty = filteredEntries.isEmpty
        emptyLabel.isHidden = !isEmpty
        emptyLabel.stringValue = query.isEmpty ? "Clipboard history is empty" : "No matches"

        collectionView.reloadData()
    }

    // MARK: - NSCollectionViewDataSource

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        filteredEntries.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: cardCellID, for: indexPath)
        if let cardItem = item as? ClipboardCardItem {
            cardItem.cardView?.themeBackground = themeBackground
            cardItem.cardView?.isDark = isDark
            cardItem.cardView?.onDelete = { [weak self] id in
                ClipboardStore.shared.deleteEntry(id: id)
                self?.reloadEntries()
            }
            cardItem.cardView?.configure(with: filteredEntries[indexPath.item], searchQuery: currentSearchQuery)
        }
        return item
    }

    // MARK: - NSCollectionViewDelegateFlowLayout

    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        let availableWidth = collectionView.bounds.width - sectionInsets.left - sectionInsets.right
        let columns = max(1, floor((availableWidth + tileSpacing) / (tileMinWidth + tileSpacing)))
        let tileWidth = floor((availableWidth - tileSpacing * (columns - 1)) / columns)
        return NSSize(width: tileWidth, height: tileHeight)
    }

    // MARK: - Theme

    private func applyTheme() {
        layer?.backgroundColor = themeBackground.cgColor
        searchField.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        reloadEntries()
    }
}
