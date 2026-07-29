import AppKit

enum BundledDocument {
    case openSourceLicenses

    var title: String {
        switch self {
        case .openSourceLicenses:
            "Open Source Licenses"
        }
    }

    private var resourceName: String {
        switch self {
        case .openSourceLicenses:
            "OpenSourceLicenses"
        }
    }

    func text(in bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: resourceName, withExtension: "md"),
              let content = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "Resource not found. Please check your installation."
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class DocumentViewController: NSViewController {
    private let document: BundledDocument

    init(document: BundledDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            view = scrollView
            return
        }

        textView.string = document.text()
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.setAccessibilityLabel(document.title)
        view = scrollView
    }
}
