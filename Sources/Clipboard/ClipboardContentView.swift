import Cocoa

private let cardCellID = NSUserInterfaceItemIdentifier("ClipboardCard")
private let tileMinWidth: CGFloat = 200
private let tileHeight: CGFloat = 110
private let tileSpacing: CGFloat = 8
private let sectionInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

// MARK: - Non-interactive text field (prevents I-beam cursor from NSTextFieldCell)

private class CardTextField: NSTextField {
    override func resetCursorRects() {
        discardCursorRects()
    }

    convenience init(label string: String) {
        self.init(frame: .zero)
        stringValue = string
        isEditable = false
        isSelectable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
    }
}

// MARK: - Clipboard card view

private class ClipboardCardView: NSView {
    private let previewLabel = CardTextField(label: "")
    private let imageView = NSImageView()
    private let timestampLabel = CardTextField(label: "")
    private let deleteButton = NSButton()
    private let copiedBadge = CardTextField(label: "Copied")
    private let zoomButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { updateBackground(); updateHoverControls() } }
    private var entry: ClipboardEntry?
    private var copiedFlashWork: DispatchWorkItem?
    var onDelete: ((UUID) -> Void)?
    var onZoom: ((ClipboardEntry) -> Void)?

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

        zoomButton.translatesAutoresizingMaskIntoConstraints = false
        zoomButton.bezelStyle = .inline
        zoomButton.isBordered = false
        let zoomConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        zoomButton.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Preview")?
            .withSymbolConfiguration(zoomConfig)
        zoomButton.imagePosition = .imageOnly
        zoomButton.target = self
        zoomButton.action = #selector(zoomClicked)
        zoomButton.isHidden = true
        zoomButton.contentTintColor = .secondaryLabelColor

        addSubview(imageView)
        addSubview(previewLabel)
        addSubview(timestampLabel)
        addSubview(deleteButton)
        addSubview(zoomButton)
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

            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            deleteButton.centerYAnchor.constraint(equalTo: timestampLabel.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 12),
            deleteButton.heightAnchor.constraint(equalToConstant: 12),

            zoomButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -6),
            zoomButton.centerYAnchor.constraint(equalTo: timestampLabel.centerYAnchor),
            zoomButton.widthAnchor.constraint(equalToConstant: 12),
            zoomButton.heightAnchor.constraint(equalToConstant: 12),

            copiedBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            copiedBadge.centerYAnchor.constraint(equalTo: timestampLabel.centerYAnchor),
        ])
    }

    private func updateHoverControls() {
        let showingCopied = !copiedBadge.isHidden
        deleteButton.isHidden = !isHovered || showingCopied
        zoomButton.isHidden = !isHovered || showingCopied
    }

    @objc private func deleteClicked() {
        guard let entry else { return }
        onDelete?(entry.id)
    }

    @objc private func zoomClicked() {
        guard let entry else { return }
        onZoom?(entry)
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
        zoomButton.isHidden = true
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
        zoomButton.isHidden = true

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

// MARK: - Preview overlay

private class ClipboardPreviewOverlay: NSView {
    private let scrimView = NSView()
    private let panelView = NSView()
    private let contentScrollView = NSScrollView()
    private let imageView = NSImageView()
    private let closeButton = NSButton()
    private let timestampLabel = CardTextField(label: "")
    private let copyButton = NSButton()
    private var textView: NSTextView?
    private var eventMonitor: Any?
    private var entry: ClipboardEntry?
    var onDismiss: (() -> Void)?

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

        scrimView.translatesAutoresizingMaskIntoConstraints = false
        scrimView.wantsLayer = true
        scrimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        addSubview(scrimView)

        panelView.translatesAutoresizingMaskIntoConstraints = false
        panelView.wantsLayer = true
        panelView.layer?.cornerRadius = 12
        panelView.layer?.masksToBounds = true
        addSubview(panelView)

        contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.drawsBackground = false
        contentScrollView.hasVerticalScroller = true
        contentScrollView.autohidesScrollers = true
        contentScrollView.borderType = .noBorder
        panelView.addSubview(contentScrollView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignCenter
        imageView.isHidden = true
        panelView.addSubview(imageView)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        let closeConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")?
            .withSymbolConfiguration(closeConfig)
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        panelView.addSubview(closeButton)

        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.font = NSFont.systemFont(ofSize: 11)
        timestampLabel.isSelectable = false
        panelView.addSubview(timestampLabel)

        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.title = "Copy"
        copyButton.bezelStyle = .accessoryBarAction
        copyButton.font = NSFont.systemFont(ofSize: 11)
        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        panelView.addSubview(copyButton)

        // Separator line above bottom bar
        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        panelView.addSubview(separator)

        NSLayoutConstraint.activate([
            scrimView.topAnchor.constraint(equalTo: topAnchor),
            scrimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrimView.bottomAnchor.constraint(equalTo: bottomAnchor),

            panelView.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            panelView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            panelView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            panelView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -32),

            closeButton.topAnchor.constraint(equalTo: panelView.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),

            contentScrollView.topAnchor.constraint(equalTo: panelView.topAnchor, constant: 12),
            contentScrollView.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 12),
            contentScrollView.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -12),
            contentScrollView.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -8),

            imageView.topAnchor.constraint(equalTo: panelView.topAnchor, constant: 12),
            imageView.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 12),
            imageView.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -12),
            imageView.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -8),

            separator.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            separator.bottomAnchor.constraint(equalTo: timestampLabel.topAnchor, constant: -8),

            timestampLabel.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 12),
            timestampLabel.bottomAnchor.constraint(equalTo: panelView.bottomAnchor, constant: -10),

            copyButton.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -12),
            copyButton.centerYAnchor.constraint(equalTo: timestampLabel.centerYAnchor),
        ])

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.superview != nil else { return event }
            if event.keyCode == 53 {
                self.onDismiss?()
                return nil
            }
            return event
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !panelView.frame.contains(point) {
            onDismiss?()
        }
    }

    func configure(with entry: ClipboardEntry, themeBackground: NSColor, isDark: Bool) {
        self.entry = entry

        let blend: NSColor = isDark ? .white : .black
        let panelBg = themeBackground.blended(withFraction: isDark ? 0.07 : 0.10, of: blend) ?? themeBackground
        panelView.layer?.backgroundColor = panelBg.cgColor

        let labelColor: NSColor = isDark
            ? NSColor.white.withAlphaComponent(0.5)
            : NSColor.black.withAlphaComponent(0.5)
        timestampLabel.textColor = labelColor
        closeButton.contentTintColor = labelColor
        timestampLabel.stringValue = relativeTime(from: entry.timestamp)

        switch entry.kind {
        case .text:
            imageView.isHidden = true
            contentScrollView.isHidden = false

            let textColor: NSColor = isDark ? .white : .black
            let tv = NSTextView()
            tv.isEditable = false
            tv.isSelectable = true
            tv.drawsBackground = false
            tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            tv.textColor = textColor
            tv.string = entry.text ?? ""
            tv.textContainerInset = NSSize(width: 4, height: 4)
            tv.isVerticallyResizable = true
            tv.isHorizontallyResizable = false
            tv.textContainer?.widthTracksTextView = true
            tv.autoresizingMask = [.width]
            contentScrollView.documentView = tv
            textView = tv

        case .image:
            contentScrollView.isHidden = true
            imageView.isHidden = false
            if let fileName = entry.imageFileName {
                let fileURL = ClipboardStore.shared.imagesDirectory.appendingPathComponent(fileName)
                imageView.image = NSImage(contentsOf: fileURL)
            }
        }
    }

    func animateIn() {
        alphaValue = 0
        panelView.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.95, y: 0.95))

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
            self.panelView.layer?.setAffineTransform(.identity)
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: completion)
    }

    @objc private func closeClicked() { onDismiss?() }

    @objc private func copyClicked() {
        guard let entry else { return }
        ClipboardStore.shared.copyToClipboard(entry)
        copyButton.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.copyButton.title = "Copy"
        }
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

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
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
    private let clearAllButton = NSButton()
    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var filteredEntries: [ClipboardEntry] = []
    private var clipboardObserver: Any?
    private var tabSelectedObserver: Any?
    private var lastLayoutWidth: CGFloat = 0
    private var currentSearchQuery: String = ""
    private var previewOverlay: ClipboardPreviewOverlay?

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

        // Clear all button
        clearAllButton.translatesAutoresizingMaskIntoConstraints = false
        clearAllButton.title = "Clear all"
        clearAllButton.bezelStyle = .accessoryBarAction
        clearAllButton.font = NSFont.systemFont(ofSize: 11)
        clearAllButton.target = self
        clearAllButton.action = #selector(clearAllClicked)

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
        addSubview(clearAllButton)
        addSubview(scrollView)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: clearAllButton.leadingAnchor, constant: -8),
            searchField.heightAnchor.constraint(equalToConstant: 32),

            clearAllButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            clearAllButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

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

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(visibleRect, cursor: .arrow)
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

    @objc private func clearAllClicked() {
        guard !ClipboardStore.shared.entries.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "This will delete all \(ClipboardStore.shared.entries.count) entries. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear all")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ClipboardStore.shared.clearAll()
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
            cardItem.cardView?.onZoom = { [weak self] entry in
                self?.showPreview(for: entry)
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

    // MARK: - Preview

    private func showPreview(for entry: ClipboardEntry) {
        dismissPreview()
        let overlay = ClipboardPreviewOverlay(frame: bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.configure(with: entry, themeBackground: themeBackground, isDark: isDark)
        overlay.onDismiss = { [weak self] in
            self?.dismissPreview()
        }
        addSubview(overlay)
        previewOverlay = overlay
        overlay.animateIn()
    }

    private func dismissPreview() {
        guard let overlay = previewOverlay else { return }
        previewOverlay = nil
        overlay.animateOut {
            overlay.removeFromSuperview()
        }
    }

    // MARK: - Theme

    private func applyTheme() {
        layer?.backgroundColor = themeBackground.cgColor
        searchField.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        reloadEntries()
    }
}
