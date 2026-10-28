import UIKit

// Synthetic reference application only; no Jolene/RN code, network or storage.
@main
final class UIKitOtpReferenceApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Reference", sessionRole: session.role)
        configuration.delegateClass = UIKitOtpReferenceScene.self
        return configuration
    }
}

final class UIKitOtpReferenceScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIKitOtpReferenceController()
        self.window = window
        window.makeKeyAndVisible()
    }
}

// Serialize only when accessibility reads this view. Input callbacks perform no
// disk/log I/O, dispatch, text assignment, cursor assignment or UI update.
private final class ReferenceMetricsView: UIView {
    var readMetrics: (() -> String)?
    override var accessibilityValue: String? {
        get { readMetrics?() }
        set { }
    }
}

private final class UIKitOtpReferenceController: UIViewController, UITextFieldDelegate {
    private let field = UITextField()
    private var events: [[String: Any]] = []
    private var truncated = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let title = UILabel()
        title.text = "Témoin UIKit · saisie synthétique"
        title.accessibilityIdentifier = "uikit-reference-title"
        title.numberOfLines = 0
        title.font = .preferredFont(forTextStyle: .headline)

        field.accessibilityIdentifier = "uikit-reference-otp"
        field.accessibilityLabel = "Code synthétique UIKit, six chiffres"
        field.placeholder = "6 chiffres"
        field.borderStyle = .roundedRect
        field.keyboardType = .numberPad
        field.textContentType = .oneTimeCode
        field.autocorrectionType = .no
        field.isSecureTextEntry = false
        field.clearsOnInsertion = false
        field.returnKeyType = .default
        field.delegate = self
        field.addTarget(self, action: #selector(editingChanged), for: .editingChanged)

        let metrics = ReferenceMetricsView()
        metrics.isAccessibilityElement = true
        metrics.accessibilityIdentifier = "uikit-reference-metrics"
        metrics.accessibilityLabel = "Mesures du témoin UIKit"
        metrics.accessibilityTraits = .staticText
        metrics.readMetrics = { [weak self] in self?.metricsJSON() ?? "unavailable" }
        let stack = UIStackView(arrangedSubviews: [title, field, metrics])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            field.heightAnchor.constraint(equalToConstant: 54),
            metrics.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        let length = (textField.text ?? "").utf16.count
        let validRange = range.location <= length && range.length <= length - range.location
        let nextLength = validRange ? length - range.length + string.utf16.count : -1
        let allowed = validRange && nextLength <= 6
        record("should-change", details: ["rangeStart": range.location, "rangeLength": range.length,
            "replacementLength": string.utf16.count, "nextLength": nextLength, "allowed": allowed])
        // UIKit has no maxLength property. This rejects an overlong replacement;
        // unlike RN it does not truncate it. Six zeros from empty exercise neither.
        return allowed
    }

    @objc private func editingChanged() { record("editing-changed") }
    func textFieldDidChangeSelection(_ textField: UITextField) { record("selection") }
    func textFieldDidBeginEditing(_ textField: UITextField) { record("focus") }
    func textFieldDidEndEditing(_ textField: UITextField) { record("blur") }

    private func selection() -> [String: Any] {
        guard let range = field.selectedTextRange else { return ["selectionPresent": false] }
        return ["selectionPresent": true,
            "selectionStart": field.offset(from: field.beginningOfDocument, to: range.start),
            "selectionEnd": field.offset(from: field.beginningOfDocument, to: range.end)]
    }

    private func record(_ kind: String, details: [String: Any] = [:]) {
        guard events.count < 64 else { truncated = true; return }
        var event: [String: Any] = ["sequence": events.count + 1, "event": kind,
            "atMs": Int64(Date().timeIntervalSince1970 * 1000),
            "length": (field.text ?? "").utf16.count, "focused": field.isFirstResponder]
        event.merge(selection()) { _, new in new }
        event.merge(details) { _, new in new }
        events.append(event)
    }

    private func metricsJSON() -> String {
        var snapshot: [String: Any] = ["schemaVersion": 1,
            "source": "synthetic-uikit-reference", "bundleId": Bundle.main.bundleIdentifier ?? "",
            "keyboard": "numberPad", "contentType": "oneTimeCode", "maximumLength": 6,
            "length": (field.text ?? "").utf16.count, "focused": field.isFirstResponder,
            "truncated": truncated, "events": events]
        snapshot.merge(selection()) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "invalid-metrics" }
        return json
    }
}
