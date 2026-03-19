import SnapshotTesting
import Testing
import LocalExamplePackage
import HostedSnapshotHelper
import SwiftUI

#if canImport(UIKit)
@MainActor
struct HostedViewSnapshotTests {
    
    @Test
    func testClosedState() {
        let sut = SheetView()
        
        assertSnapshot(
            of: sut,
            as: .image(layout: .device(config: .iPhone13))
        )
    }
    
    @Test(.requiresKeyWindow)
    func testSheetViewSheetOpenState() {
        let sut = SheetView(isSheetPresented: true, toggleOn: false)

        assertHostedSnapshot(of: sut, devices: [("iPhone13", .iPhone13)], wait: 1.0)
    }

    @Test(.requiresKeyWindow)
    func testAlertViewSheetOpenState() {
        let sut = AlertView(isAlertPresented: true, toggleOn: true)

        assertHostedSnapshot(of: sut, devices: [("iPhone13", .iPhone13)], wait: 1.0)
    }
}
#endif
