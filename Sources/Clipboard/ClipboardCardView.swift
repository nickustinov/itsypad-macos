import Cocoa

class ClipboardCardView: NSView {
    private let previewLabel = CardTextField(label: "")
    private let imageView = NSImageView()
    private let timestampLabel = CardTextField(label: "")
    private let deleteButton = NSButton()
    private let shortcutBadgeLabel = CardTextField(label: "")
    private let copiedBadge = CardTextField(label: String(localized: "clipboard.copied", defaultValue: "Copied"))
    private let zoomButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { updateBackground(); updateHoverControls() } }
    private var entry: ClipboardEntry?
    private var copiedFlashWork: DispatchWorkItem?
    var onDelete: ((UUID) -> Void)?
    var onZoom: ((ClipboardEntry) -> Void)?
    var onActivate: ((ClipboardEntry) -> Void)?

    var themeBackground: NSColor = .windowBackgroundColor { didSet { updateBackground() } }
    var isDark: Bool = false { didSet { updateAppearance() } }
    var isCardSelected: Bool = false { didSet { updateBackground() } }

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
        previewLabel.maximumNumberOfLines = SettingsStore.shared.clipboardPreviewLines
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.font = NSFont.monospacedSystemFont(ofSize: CGFloat(SettingsStore.shared.clipboardFontSize), weight: .regular)
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
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: String(localized: "clipboard.card.delete", defaultValue: "Delete"))?.withSymbolConfiguration(smallConfig)
        deleteButton.imagePosition = .imageOnly
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        deleteButton.isHidden = true
        deleteButton.contentTintColor = .secondaryLabelColor

        shortcutBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutBadgeLabel.font = NSFont.systemFont(ofSize: 10)
        shortcutBadgeLabel.textColor = .secondaryLabelColor
        shortcutBadgeLabel.isSelectable = false
        shortcutBadgeLabel.isHidden = true

        copiedBadge.translatesAutoresizingMaskIntoConstraints = false
        copiedBadge.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        copiedBadge.textColor = .secondaryLabelColor
        copiedBadge.isSelectable = false
        copiedBadge.isHidden = true

        zoomButton.translatesAutoresizingMaskIntoConstraints = false
        zoomButton.bezelStyle = .inline
        zoomButton.isBordered = false
        let zoomConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        zoomButton.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: String(localized: "clipboard.card.preview", defaultValue: "Preview"))?
            .withSymbolConfiguration(zoomConfig)
        zoomButton.imagePosition = .imageOnly
        zoomButton.target = self
        zoomButton.action = #selector(zoomClicked)
        zoomButton.isHidden = true
        zoomButton.contentTintColor = .secondaryLabelColor

        addSubview(imageView)
        addSubview(previewLabel)
        addSubview(timestampLabel)
        addSubview(shortcutBadgeLabel)
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

            shortcutBadgeLabel.leadingAnchor.constraint(equalTo: timestampLabel.trailingAnchor, constant: 6),
            shortcutBadgeLabel.centerYAnchor.constraint(equalTo: timestampLabel.centerYAnchor),
            shortcutBadgeLabel.trailingAnchor.constraint(lessThanOrEqualTo: zoomButton.leadingAnchor, constant: -6),

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

    func configure(with entry: ClipboardEntry, searchQuery: String = "", shortcutIndex: Int? = nil) {
        self.entry = entry
        previewLabel.maximumNumberOfLines = SettingsStore.shared.clipboardPreviewLines

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

        timestampLabel.stringValue = clipboardRelativeTime(from: entry.timestamp)

        if let index = shortcutIndex {
            let n = index + 1
            shortcutBadgeLabel.stringValue = "\u{2318}\(n)  \u{2325}\(n)"
            shortcutBadgeLabel.isHidden = false
        } else {
            shortcutBadgeLabel.isHidden = true
        }

        updateBackground()
    }

    private func configureTextPreview(text: String, searchQuery: String) {
        let fontSize = CGFloat(SettingsStore.shared.clipboardFontSize)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
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
            let previewLines = SettingsStore.shared.clipboardPreviewLines
            if matchLine > 2, trimmed.count > previewLines {
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
        shortcutBadgeLabel.isHidden = true
        deleteButton.isHidden = true
        zoomButton.isHidden = true
        isHovered = false
        isCardSelected = false
        imageView.image = nil
        imageView.isHidden = true
        previewLabel.isHidden = false
    }

    private func updateAppearance() {
        previewLabel.textColor = isDark ? .white : .black
        let secondaryColor = isDark
            ? NSColor.white.withAlphaComponent(0.5)
            : NSColor.black.withAlphaComponent(0.5)
        timestampLabel.textColor = secondaryColor
        shortcutBadgeLabel.textColor = secondaryColor
        updateBackground()
    }

    private func updateBackground() {
        let blend: NSColor = isDark ? .white : .black
        let fraction: CGFloat = isDark ? (isHovered ? 0.12 : 0.07) : (isHovered ? 0.20 : 0.15)
        let cardBg = themeBackground.blended(withFraction: fraction, of: blend) ?? themeBackground
        layer?.backgroundColor = cardBg.cgColor
        if isCardSelected {
            layer?.borderWidth = 2
            layer?.borderColor = NSColor.controlAccentColor.cgColor
        } else {
            layer?.borderWidth = 0
        }
    }

    @objc private func cardClicked() {
        guard let entry else { return }
        if let onActivate {
            onActivate(entry)
        } else {
            ClipboardStore.shared.copyToClipboard(entry)
            showCopiedFlash()
        }
    }

    func flashCopied() { showCopiedFlash() }

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
}
