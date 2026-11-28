import SwiftUI

@main
enum NanZipMain {
    static func main() {
        let firstArgument = CommandLine.arguments.dropFirst().first
        if firstArgument == "--self-test" || firstArgument == "--compress-test" ||
            firstArgument == "--volume-test" || firstArgument == "--replace-test" ||
            firstArgument == "--delete-test" || firstArgument == "--repair-test" ||
            firstArgument == "--xpc-test" || firstArgument == "--xpc-internal-test" ||
            firstArgument == "--xpc-ping-test" || firstArgument == "--keychain-test" {
            NanZipSelfTest.run()
        }
        NanZipApp.main()
    }
}

struct NanZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1080, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开压缩包…") {
                    model.selectMode(.extract)
                    model.presentOpenPanel()
                }
                .keyboardShortcut("o")

                Button("压缩文件…") {
                    model.selectMode(.compress)
                    model.presentCompressionInputPanel()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 520, height: 360)
        }
    }
}
