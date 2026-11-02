import SwiftUI

enum RadioTheme {
    static let ink = Color(red: 0.129, green: 0.110, blue: 0.106)
    static let panel = Color(red: 0.188, green: 0.153, blue: 0.137)
    static let gold = Color(red: 0.878, green: 0.667, blue: 0.420)
    static let pale = Color(red: 0.945, green: 0.882, blue: 0.790)
    static let line = Color(red: 0.455, green: 0.345, blue: 0.267)
    static let soft = Color(red: 0.286, green: 0.224, blue: 0.184)
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
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(RadioTheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(RadioTheme.line, lineWidth: 1.2)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            )
    }
}
