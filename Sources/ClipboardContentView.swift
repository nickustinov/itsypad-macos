import Cocoa

// MARK: - Clipboard card view

private class ClipboardCardView: NSView {
    private let previewLabel = NSTextField(wrappingLabelWithString: "")
    private let timestampLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { updateBackground() } }
    private var entry: ClipboardEntry?
    private var copiedFlashWork: DispatchWorkItem?

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
        previewLabel.maximumNumberOfLines = 3
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        previewLabel.isSelectable = false

        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.font = NSFont.systemFont(ofSize: 10)
        timestampLabel.textColor = .secondaryLabelColor
        timestampLabel.isSelectable = false

        addSubview(previewLabel)
        addSubview(timestampLabel)

        NSLayoutConstraint.activate([
            previewLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            previewLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            previewLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            timestampLabel.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 4),
            timestampLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            timestampLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            timestampLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(cardClicked))
        addGestureRecognizer(click)
    }

    func configure(with entry: ClipboardEntry) {
        self.entry = entry
        let preview = String(entry.content.prefix(500))
        previewLabel.stringValue = preview
        timestampLabel.stringValue = relativeTime(from: entry.timestamp)
        updateBackground()
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
        let fraction: CGFloat = isHovered ? 0.15 : 0.10
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

        let savedText = previewLabel.stringValue
        previewLabel.stringValue = "Copied!"
        previewLabel.textColor = .controlAccentColor

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.previewLabel.stringValue = savedText
            self.updateAppearance()
        }
        copiedFlashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

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

// MARK: - Flipped clip view (anchors content to top)

private class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

// MARK: - Clipboard content view

class ClipboardContentView: NSView {
    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private var clipboardObserver: Any?

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

        // Scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        // Stack view
        stackView.orientation = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stackView.alignment = .leading
        stackView.setHuggingPriority(.defaultHigh, for: .vertical)

        let clipView = FlippedClipView()
        clipView.documentView = stackView
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        addSubview(searchField)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            searchField.heightAnchor.constraint(equalToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: clipView.topAnchor),
        ])

        // Pin bottom with low priority so content anchors to top when shorter than scroll area
        let bottomPin = stackView.bottomAnchor.constraint(lessThanOrEqualTo: clipView.bottomAnchor)
        bottomPin.priority = .defaultLow
        bottomPin.isActive = true

        clipboardObserver = NotificationCenter.default.addObserver(
            forName: ClipboardStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadEntries()
        }

        reloadEntries()
    }

    deinit {
        if let observer = clipboardObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @objc private func searchChanged() {
        reloadEntries()
    }

    func reloadEntries() {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let query = searchField.stringValue
        let entries = ClipboardStore.shared.search(query: query)

        if entries.isEmpty {
            let emptyLabel = NSTextField(labelWithString: query.isEmpty ? "Clipboard history is empty" : "No matches")
            emptyLabel.font = NSFont.systemFont(ofSize: 12)
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(emptyLabel)
            return
        }

        for entry in entries {
            let card = ClipboardCardView(frame: .zero)
            card.translatesAutoresizingMaskIntoConstraints = false
            card.themeBackground = themeBackground
            card.isDark = isDark
            card.configure(with: entry)
            stackView.addArrangedSubview(card)

            card.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -24).isActive = true
        }
    }

    private func applyTheme() {
        layer?.backgroundColor = themeBackground.cgColor
        let blend: NSColor = isDark ? .white : .black
        searchField.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        _ = themeBackground.blended(withFraction: 0.05, of: blend)
        reloadEntries()
    }
}
