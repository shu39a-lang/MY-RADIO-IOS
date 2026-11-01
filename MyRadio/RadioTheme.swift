import SwiftUI

enum RadioTheme {
    static let ink = Color(red: 0.055, green: 0.080, blue: 0.14)
    static let panel = Color(red: 0.10, green: 0.13, blue: 0.21)
    static let gold = Color(red: 1.0, green: 0.75, blue: 0.40)
    static let pale = Color(red: 0.77, green: 0.80, blue: 0.85)
}

struct RadioPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RadioTheme.panel, in: RoundedRectangle(cornerRadius: 22))
    }
}
