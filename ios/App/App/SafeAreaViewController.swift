import UIKit
import WebKit
import Capacitor

// v2 — إصلاح «الهيدر ينزل عند دخول المحادثة/بعد الكتابة» (شكاوى ٢٨ أغسطس، ٥ آيفونات):
//
// 1) النسخة السابقة كانت تثبّت الويب تحت شريط الساعة (safeAreaLayoutGuide)
//    بينما الموقع نفسه يضيف حاشية env(safe-area-inset-top) — فيتضاعف الفراغ.
//    الموقع مصمم لملء الشاشة ويتكفل بمناطق الأمان بنفسه، فالويب يُثبّت الآن
//    على حواف الشاشة كاملة.
//
// 2) عطل WKWebView الموثق: عند فتح الكيبورد يزيح النظام محتوى الويب ليكشف
//    حقل الكتابة، وعند إغلاقه قد لا يرجع الإزاحة أبدًا — فتعلق الشاشة نازلة
//    (والمناطق اللمسية معها) حتى إعادة التحميل. جافاسكربت الصفحة لا ترى هذه
//    الإزاحة إطلاقًا (أرقامها كلها أصفار) فلا يمكن إصلاحها من الويب.
//    العلاج هنا في الطبقة الأصلية: عند كل إغلاق للكيبورد يُصفَّر انزياح
//    scrollView وحواشيه قسرًا — نفس مفعول إعادة التحميل بلا إعادة تحميل.
class SafeAreaViewController: CAPBridgeViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // #0d0d17 — نفس خلفية الموقع
        view.backgroundColor = UIColor(red: 13.0 / 255.0, green: 13.0 / 255.0, blue: 23.0 / 255.0, alpha: 1.0)

        guard let webView = self.webView else { return }
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        // قفل الشاشة: لا ارتداد مطاطي يسحب الأشرطة الثابتة، ولا حواشٍ يحقنها
        // النظام فتزيح المحتوى.
        let scrollView = webView.scrollView
        scrollView.bounces = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never

        // ملء الشاشة كاملة — الموقع يضيف حاشية شريط الساعة وشريط الهوم بنفسه
        // عبر env(safe-area-inset-*)؛ تثبيته تحت safeAreaLayoutGuide كان
        // يضاعف الفراغ (حاشية أصلية + حاشية الموقع).
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // تصفير الإزاحة العالقة عند إغلاق الكيبورد — مرتان (will + did) لأن
        // بعض نسخ iOS تعيد كتابة الانزياح بين اللحظتين.
        NotificationCenter.default.addObserver(
            self, selector: #selector(resetWebScroll),
            name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(resetWebScroll),
            name: UIResponder.keyboardDidHideNotification, object: nil)

        // v3 — جسرا التنزيل (شكوى ٢٨ أغسطس: «تحميل PDF ما يشتغل»):
        // WKWebView لا يدعم روابط التنزيل ولا window.print()، فالموقع يرسل
        // الملف/المستند إلى هذين الجسرين وتفتح ورقة مشاركة iOS الأصلية.
        let ucc = webView.configuration.userContentController
        ucc.removeScriptMessageHandler(forName: "omranPdf")
        ucc.removeScriptMessageHandler(forName: "omranShare")
        ucc.add(self, name: "omranPdf")
        ucc.add(self, name: "omranShare")
    }

    // MARK: - جسرا PDF والمشاركة

    /// HTML → PDF أصلي (A4) → ورقة مشاركة
    private func renderHtmlToPdfAndShare(html: String, fileName: String) {
        DispatchQueue.main.async {
            let formatter = UIMarkupTextPrintFormatter(markupText: html)
            let renderer = UIPrintPageRenderer()
            renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
            let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4 بالنقاط
            renderer.setValue(page, forKey: "paperRect")
            renderer.setValue(page.insetBy(dx: 24, dy: 28), forKey: "printableRect")
            let data = NSMutableData()
            UIGraphicsBeginPDFContextToData(data, page, nil)
            let pages = max(1, renderer.numberOfPages)
            for i in 0..<pages {
                UIGraphicsBeginPDFPage()
                renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
            }
            UIGraphicsEndPDFContext()
            self.shareFile(data: data as Data, fileName: fileName)
        }
    }

    /// ملف جاهز → ورقة مشاركة iOS (حفظ في الملفات / إرسال / طباعة…)
    private func shareFile(data: Data, fileName: String) {
        DispatchQueue.main.async {
            let safeName = fileName.replacingOccurrences(of: "/", with: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
            do { try data.write(to: url, options: .atomic) } catch { return }
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let pop = sheet.popoverPresentationController {
                pop.sourceView = self.view
                pop.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
            }
            (self.presentedViewController ?? self).present(sheet, animated: true)
        }
    }

    @objc private func resetWebScroll() {
        guard let scrollView = self.webView?.scrollView else { return }
        // تأجيل إطارًا واحدًا حتى لا يسبقنا النظام بكتابة قيمه بعد الإشعار.
        DispatchQueue.main.async {
            scrollView.contentInset = .zero
            scrollView.scrollIndicatorInsets = .zero
            if scrollView.contentOffset != .zero {
                scrollView.setContentOffset(.zero, animated: false)
            }
        }
        // جولة ثانية متأخرة: حركة إغلاق الكيبورد تكتمل بعد ~0.25 ثانية وقد
        // تترك انزياحًا جديدًا بعد التصفير الأول.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard let sv = self.webView?.scrollView else { return }
            sv.contentInset = .zero
            sv.scrollIndicatorInsets = .zero
            if sv.contentOffset != .zero {
                sv.setContentOffset(.zero, animated: false)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // خلفية داكنة → نص شريط الحالة أبيض
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}

// v3 — استقبال رسائل الموقع (جسرا omranPdf / omranShare)
extension SafeAreaViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch message.name {
        case "omranPdf":
            guard let html = body["html"] as? String, !html.isEmpty else { return }
            let name = (body["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "omran-ai.pdf"
            renderHtmlToPdfAndShare(html: html, fileName: name)
        case "omranShare":
            guard let b64 = body["b64"] as? String,
                  let data = Data(base64Encoded: b64), !data.isEmpty else { return }
            let name = (body["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "omran-file"
            shareFile(data: data, fileName: name)
        default:
            break
        }
    }
}
