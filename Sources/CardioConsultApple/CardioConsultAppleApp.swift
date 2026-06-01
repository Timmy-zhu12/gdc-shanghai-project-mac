import SwiftUI

@main
struct CardioConsultAppleApp: App {
    @StateObject private var viewModel = CardioConsultViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}

