import SwiftUI

// MARK: - 自适应高度的 UITextView

/// 关闭滚动、按内容撑高的 UITextView：行内加粗/下划线/链接全部原生渲染
final class SelfSizingTextView: UITextView {
    override var intrinsicContentSize: CGSize {
        let available = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        let fitting = sizeThatFits(CGSize(width: available, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(fitting.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }
}

// MARK: - 富文本视图

struct RichText: UIViewRepresentable {

    let attributed: NSAttributedString
    var linkColor: UIColor = .tintColor
    var lineSpacing: CGFloat = 6
    var alignment: NSTextAlignment = .left
    var onLink: ((URL) -> Void)?

    func makeUIView(context: Context) -> SelfSizingTextView {
        let tv = SelfSizingTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.lineBreakMode = .byTruncatingTail
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.required, for: .vertical)
        tv.delegate = context.coordinator
        return tv
    }

    func updateUIView(_ uiView: SelfSizingTextView, context: Context) {
        context.coordinator.onLink = onLink

        let mutable = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: mutable.length)

        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = lineSpacing * 1.4
        style.alignment = alignment
        mutable.addAttribute(.paragraphStyle, value: style, range: full)

        uiView.attributedText = mutable
        uiView.linkTextAttributes = [
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        uiView.invalidateIntrinsicContentSize()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onLink: ((URL) -> Void)?

        func textView(
            _ textView: UITextView,
            shouldInteractWith URL: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            guard interaction == .invokeDefaultAction else { return true }
            onLink?(URL)
            return false
        }
    }
}

// MARK: - Inline → NSAttributedString

enum InlineRenderer {

    static func render(
        _ spans: [Inline],
        fontSize: CGFloat = 17,
        weight: UIFont.Weight = .regular,
        color: UIColor = .label,
        alignment: NSTextAlignment = .left
    ) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let base = UIFont.preferredFont(forTextStyle: .body)
        let size = fontSize

        for span in spans {
            switch span {
            case .text(let value, let bold, let underline, let italic):
                out.append(
                    piece(
                        value,
                        font: resolvedFont(base: base, size: size, weight: weight, bold: bold, italic: italic),
                        color: color,
                        underline: underline
                    )
                )
            case .link(let text, let url, let bold, _):
                let piece = self.piece(
                    text,
                    font: resolvedFont(base: base, size: size, weight: weight, bold: bold, italic: false),
                    color: .tintColor,
                    underline: true
                )
                if let u = URL(string: url) { piece.addAttribute(.link, value: u, range: NSRange(location: 0, length: piece.length)) }
                out.append(piece)
            }
        }
        return NSAttributedString(attributedString: out)
    }

    private static func piece(
        _ text: String,
        font: UIFont,
        color: UIColor,
        underline: Bool
    ) -> NSMutableAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        if underline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return NSMutableAttributedString(string: text, attributes: attrs)
    }

    private static func resolvedFont(
        base: UIFont,
        size: CGFloat,
        weight: UIFont.Weight,
        bold: Bool,
        italic: Bool
    ) -> UIFont {
        var traits = base.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) } else { traits.remove(.traitBold) }
        if italic { traits.insert(.traitItalic) } else { traits.remove(.traitItalic) }
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor
        let w: UIFont.Weight = bold ? .semibold : weight
        return UIFont(descriptor: descriptor, size: size).rounded(weight: w)
    }
}

extension UIFont {
    /// 按字重取圆体 / 系统字体，保持中英文观感统一
    func rounded(weight: UIFont.Weight) -> UIFont {
        let d = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: d, size: pointSize)
    }
}
