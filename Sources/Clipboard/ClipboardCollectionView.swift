import Cocoa

protocol ClipboardCollectionViewKeyDelegate: AnyObject {
    func collectionViewKeyDown(with event: NSEvent) -> Bool
}

class ClipboardCollectionView: NSCollectionView {
    weak var keyDelegate: ClipboardCollectionViewKeyDelegate?

    override func keyDown(with event: NSEvent) {
        if keyDelegate?.collectionViewKeyDown(with: event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func moveUp(_ sender: Any?) { _ = keyDelegate?.collectionViewKeyDown(with: syntheticEvent(keyCode: 126)) }
    override func moveDown(_ sender: Any?) { _ = keyDelegate?.collectionViewKeyDown(with: syntheticEvent(keyCode: 125)) }
    override func moveLeft(_ sender: Any?) { _ = keyDelegate?.collectionViewKeyDown(with: syntheticEvent(keyCode: 123)) }
    override func moveRight(_ sender: Any?) { _ = keyDelegate?.collectionViewKeyDown(with: syntheticEvent(keyCode: 124)) }

    private func syntheticEvent(keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window?.windowNumber ?? 0,
            context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: keyCode
        ) ?? NSEvent()
    }
}
