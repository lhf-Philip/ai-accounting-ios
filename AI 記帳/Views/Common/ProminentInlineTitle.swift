import SwiftUI
import UIKit

struct ProminentInlineTitleModifier: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}

extension View {
    func prominentInlineTitle(_ title: String) -> some View {
        modifier(ProminentInlineTitleModifier(title: title))
    }

    func keyboardDoneToolbar(title: String = "完成") -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(title) {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }
            }
        }
    }

    func interactiveKeyboardDismiss() -> some View {
        scrollDismissesKeyboard(.interactively)
    }
}
