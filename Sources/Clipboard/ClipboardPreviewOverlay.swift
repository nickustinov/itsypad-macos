import Cocoa

class ClipboardPreviewOverlay: NSView {
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
    var onNavigate: ((UInt16) -> Void)?

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
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: String(localized: "clipboard.preview.close", defaultValue: "Close"))?
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
        copyButton.title = String(localized: "clipboard.preview.copy", defaultValue: "Copy")
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
            switch event.keyCode {
            case 53: // escape
                self.onDismiss?()
                return nil
            case 123, 124, 125, 126, 49: // arrows + space
                self.onNavigate?(event.keyCode)
                return nil
            default:
                return event
            }
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
        timestampLabel.stringValue = clipboardRelativeTime(from: entry.timestamp)

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
        copyButton.title = String(localized: "clipboard.preview.copied", defaultValue: "Copied!")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.copyButton.title = String(localized: "clipboard.preview.copy", defaultValue: "Copy")
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
