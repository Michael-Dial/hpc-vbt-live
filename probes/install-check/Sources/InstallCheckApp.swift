import SwiftUI
import UIKit

@main
struct InstallCheckApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Text("VBT install check").font(.title2).bold()
                Text(UIDevice.current.name)
                Text("iOS \(UIDevice.current.systemVersion)")
                Text(Bundle.main.bundleIdentifier ?? "no bundle ID").font(.footnote)
            }
            .padding()
        }
    }
}
