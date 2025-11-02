import Cocoa

let screens = NSScreen.screens

func printWidth(of screen: NSScreen) {
    let width = Int(screen.frame.width)
    print(width)
}

let args = CommandLine.arguments
if args.count > 1 {
    let targetName = args[1]
    if let screen = screens.first(where: { $0.localizedName == targetName }) {
        printWidth(of: screen)
        exit(0)
    }
}

if let main = NSScreen.main {
    printWidth(of: main)
} else if let first = screens.first {
    printWidth(of: first)
} else {
    print(0)
}
