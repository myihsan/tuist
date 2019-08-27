import Basic
import Foundation
import TuistCore

class MockPrinter: Printing {
    func print(_: String, output _: PrinterOutput) {}

    func print(_: String) {}

    func print(_: String, color _: TerminalController.Color) {}

    func print(section _: String) {}

    func print(subsection _: String) {}

    func print(warning _: String) {}

    func print(error _: Error) {}

    func print(success _: String) {}

    func print(errorMessage _: String) {}

    func print(deprecation _: String) {}
}
