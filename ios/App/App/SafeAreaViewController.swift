import UIKit
import WebKit
import Capacitor

// Keeps the web content inside the device safe area so the page is not
// clipped by the notch / status bar at the top or the home indicator at
// the bottom. The area outside the web view is painted with the app's
// dark theme color so it blends with the site.
class SafeAreaViewController: CAPBridgeViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // #0d0d17 — same background as the web app
        view.backgroundColor = UIColor(red: 13.0 / 255.0, green: 13.0 / 255.0, blue: 23.0 / 255.0, alpha: 1.0)

        guard let webView = self.webView else { return }
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        // Lock the screen in place: no rubber-band overscroll, so fixed
        // bars (header / bottom settings bar) never drag with the page.
        let scrollView = webView.scrollView
        scrollView.bounces = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        // Don't let iOS inject its own insets and shift the content.
        scrollView.contentInsetAdjustmentBehavior = .never

        // Pin the web view to the safe area instead of the full screen.
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    // Dark background -> light status bar text
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}
