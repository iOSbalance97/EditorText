import SwiftUI
import UIKit

/// Puente entre SwiftUI y el UITextView (deshacer, buscar, ir a línea, posición del cursor).
final class EditorController: ObservableObject {
    weak var textView: UITextView?
    @Published var line = 1
    @Published var col = 1

    func updatePosition(line: Int, col: Int) {
        if self.line != line { self.line = line }
        if self.col != col { self.col = col }
    }

    func undo() { textView?.undoManager?.undo() }
    func redo() { textView?.undoManager?.redo() }
    func hideKeyboard() { textView?.resignFirstResponder() }

    /// Buscar y reemplazar con la interfaz nativa de iOS.
    func showFind() {
        guard let tv = textView else { return }
        tv.becomeFirstResponder()
        DispatchQueue.main.async {
            tv.findInteraction?.presentFindNavigator(showingReplace: true)
        }
    }

    func goTo(line: Int, focus: Bool = true) {
        guard let tv = textView else { return }
        let s = (tv.text ?? "") as NSString
        let target = max(1, line)
        var index = 0
        var current = 1
        while current < target {
            let range = s.range(of: "\n", options: [], range: NSRange(location: index, length: s.length - index))
            if range.location == NSNotFound { break }
            index = range.location + range.length
            current += 1
        }
        if focus { tv.becomeFirstResponder() }
        let caret = NSRange(location: index, length: 0)
        tv.selectedRange = caret
        tv.scrollRangeToVisible(caret)
    }
}

/// Editor de texto monoespaciado basado en UITextView.
struct CodeTextView: UIViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var hexKeyboard: Bool
    var controller: EditorController

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.autocorrectionType = .no
        tv.autocapitalizationType = hexKeyboard ? .allCharacters : .none
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.spellCheckingType = .no
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.isFindInteractionEnabled = true
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 90, right: 10)
        tv.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.text = text
        tv.inputAccessoryView = CodeTextView.makeAccessory(for: tv, hex: hexKeyboard)
        controller.textView = tv
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        if tv.font?.pointSize != fontSize {
            tv.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        if tv.text != text {
            tv.text = text
            tv.undoManager?.removeAllActions()
        }
        controller.textView = tv
    }

    // MARK: Delegado

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeTextView

        init(_ parent: CodeTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            report(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            report(textView)
        }

        private func report(_ tv: UITextView) {
            if tv.textStorage.length > 3_000_000 { return }
            let s = tv.text ?? ""
            let location = tv.selectedRange.location
            var line = 1
            var col = 1
            for unit in s.utf16.prefix(location) {
                if unit == 10 {
                    line += 1
                    col = 1
                } else {
                    col += 1
                }
            }
            let controller = parent.controller
            DispatchQueue.main.async {
                controller.updatePosition(line: line, col: col)
            }
        }
    }

    // MARK: Barra de símbolos sobre el teclado

    static func makeAccessory(for tv: UITextView, hex: Bool) -> UIView {
        let symbols: [String]
        if hex {
            symbols = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F", " ", "\n"]
        } else {
            symbols = ["\t", "{", "}", "[", "]", "(", ")", "<", ">", "=", "\"", "'", ":", ";", "/", "\\",
                       "#", "*", "&", "|", "_", "-", "+", "$", "%", "@", "!", "?", "~", "`"]
        }

        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 46))
        container.autoresizingMask = [.flexibleWidth]

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        blur.frame = container.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(blur)

        let scroll = UIScrollView(frame: container.bounds)
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.showsHorizontalScrollIndicator = false
        container.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 5
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])

        for symbol in symbols {
            var title = symbol
            if symbol == "\t" { title = "⇥" }
            if symbol == " " { title = "␣" }
            if symbol == "\n" { title = "⏎" }

            var config = UIButton.Configuration.gray()
            config.title = title
            config.cornerStyle = .capsule
            config.baseForegroundColor = UIColor.label
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)

            let action = UIAction { [weak tv] _ in
                tv?.insertText(symbol)
            }
            let button = UIButton(configuration: config, primaryAction: action)
            stack.addArrangedSubview(button)
        }

        var doneConfig = UIButton.Configuration.tinted()
        doneConfig.image = UIImage(systemName: "keyboard.chevron.compact.down")
        doneConfig.cornerStyle = .capsule
        let done = UIButton(configuration: doneConfig, primaryAction: UIAction { [weak tv] _ in
            tv?.resignFirstResponder()
        })
        stack.addArrangedSubview(done)

        return container
    }
}
