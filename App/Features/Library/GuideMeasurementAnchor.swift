#if os(iOS)
import SwiftUI
import UIKit

/// Only supplies the presenting window; it never presents or changes layout.
struct GuideMeasurementAnchor: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView {
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) { }
}
#endif
