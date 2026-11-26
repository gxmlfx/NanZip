import SwiftUI

@main
enum NanZipMain {
    static func main() {
        let firstArgument = CommandLine.arguments.dropFirst().first
        if firstArgument == "--self-test" || firstArgument == "--compress-test" {
            NanZipSelfTest.run()
        }
        NanZipApp.main()
    }
}

struct NanZipApp: App {
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
            SettingsView()
                .frame(width: 520, height: 360)
        }
    }
}
