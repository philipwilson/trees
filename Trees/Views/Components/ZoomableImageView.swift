import SwiftUI
import UIKit

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomableScrollView {
        let view = ZoomableScrollView()
        view.image = image
        return view
    }

    func updateUIView(_ view: ZoomableScrollView, context: Context) {
        if view.image !== image {
            view.image = image
        }
    }
}

class ZoomableScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()

    var image: UIImage? {
        didSet {
            imageView.image = image
            zoomScale = 1.0
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        delegate = self
        minimumZoomScale = 1.0
        maximumZoomScale = 5.0
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = .clear

        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != .zero else { return }

        if zoomScale == 1.0 {
            imageView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
        centerImage()
    }

    private func centerImage() {
        let offsetX = max((bounds.width - contentSize.width) / 2, 0)
        let offsetY = max((bounds.height - contentSize.height) / 2, 0)
        imageView.center = CGPoint(
            x: contentSize.width / 2 + offsetX,
            y: contentSize.height / 2 + offsetY
        )
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let location = gesture.location(in: imageView)
            let zoomTo = min(maximumZoomScale, 2.5)
            let size = CGSize(
                width: bounds.width / zoomTo,
                height: bounds.height / zoomTo
            )
            let origin = CGPoint(
                x: location.x - size.width / 2,
                y: location.y - size.height / 2
            )
            zoom(to: CGRect(origin: origin, size: size), animated: true)
        }
    }
}
