import Cocoa

class ClipboardCardItem: NSCollectionViewItem {
    override func loadView() {
        view = ClipboardCardView(frame: .zero)
    }

    var cardView: ClipboardCardView? { view as? ClipboardCardView }

    override func prepareForReuse() {
        super.prepareForReuse()
        cardView?.resetState()
    }
}
