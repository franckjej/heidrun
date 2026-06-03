import Cocoa
extension NSImage {
	public func image(with tintColor: NSColor) -> NSImage {
		if self.isTemplate == false {
			return self
		}

        guard let image = self.copy() as? NSImage else { return self }
		image.lockFocus()

		tintColor.set()

		let imageRect = NSRect(origin: .zero, size: image.size)
		imageRect.fill(using: .sourceIn)

		image.unlockFocus()
		image.isTemplate = false

		return image
	}

   public static func mask(withCornerRadius radius: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: radius * 2, height: radius * 2), flipped: false) {
            NSBezierPath(roundedRect: $0, xRadius: radius, yRadius: radius).fill()
            NSColor.black.set()
            return true
        }

        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch

        return image
    }
}
