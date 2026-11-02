import Foundation

@MainActor
final class RadioStore: ObservableObject {
    @Published var profile: ListenerProfile {
        didSet { save() }
    }
    @Published var recentTitles: [String] {
        didSet { save() }
    }
    @Published var lastProgram: RadioProgram? {
        didSet { save() }
    }
    @Published var serverURL: String {
        didSet { save() }
    }
    @Published var isGenerating = false
    @Published var errorMessage: String?

    init() {
        let defaults = UserDefaults.standard
        profile = defaults.data(forKey: "myradio.profile")
            .flatMap { try? JSONDecoder().decode(ListenerProfile.self, from: $0) } ?? ListenerProfile()
        recentTitles = defaults.stringArray(forKey: "myradio.recentTitles") ?? []
        lastProgram = defaults.data(forKey: "myradio.lastProgram")
            .flatMap { try? JSONDecoder().decode(RadioProgram.self, from: $0) }
        serverURL = defaults.string(forKey: "myradio.serverURL") ?? ""
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(profile), forKey: "myradio.profile")
        defaults.set(recentTitles, forKey: "myradio.recentTitles")
        defaults.set(try? JSONEncoder().encode(lastProgram), forKey: "myradio.lastProgram")
        defaults.set(serverURL, forKey: "myradio.serverURL")
    }

    func generate() async {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            let program = try await ProgramService.generate(profile: profile,
                                                            recentTitles: recentTitles,
                                                            endpoint: serverURL)
            lastProgram = program
            if !program.isSample {
                recentTitles = Array(([program.title] + recentTitles).prefix(8))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func makeSample() {
        lastProgram = DemoProgram.make(profile: profile)
    }

    func recordLike() {
        guard let title = lastProgram?.title else { return }
        if !profile.preferredTopics.contains(title) {
            profile.preferredTopics = Array((profile.preferredTopics + [title]).suffix(8))
        }
    }

    func erasePersonalData() {
        profile = ListenerProfile()
        recentTitles = []
        lastProgram = nil
        serverURL = ""
        CredentialVault.delete()
        NotificationService.cancel()
        errorMessage = nil
    }
}
