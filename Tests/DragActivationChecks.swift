import Cocoa

@main
struct DragActivationChecks {
    static func main() {
        for screen in [CGRect(x: 0, y: 0, width: 1512, height: 982),
                       CGRect(x: -1920, y: -200, width: 1920, height: 1080),
                       CGRect(x: 300, y: 982, width: 1440, height: 900)] {
            for size in [CGSize(width: 185, height: 32), CGSize(width: 185, height: 0)] {
                let region = DragDetector.activationRegion(screenFrame: screen, closedNotchSize: size)
                let detector = DragDetector(notchRegion: region)
                var entries = 0
                var exits = 0
                detector.onDragEntersNotchRegion = { entries += 1 }
                detector.onDragExitsNotchRegion = { exits += 1 }

                // Ordinary file rows under the notch used to fall inside the expanded trigger.
                for depth in [60.0, 100, 180, 234, 500] {
                    detector.updateDragLocation(CGPoint(x: screen.midX, y: screen.maxY - depth))
                }
                detector.updateDragLocation(CGPoint(x: screen.minX + 5, y: screen.maxY - 5))
                detector.updateDragLocation(CGPoint(x: screen.maxX - 5, y: screen.maxY - 5))
                precondition(entries == 0 && exits == 0, "Dragging elsewhere must not open Shelf")

                let nearNotch = CGPoint(x: screen.midX, y: screen.maxY - 5)
                detector.updateDragLocation(nearNotch)
                detector.updateDragLocation(nearNotch)
                precondition(entries == 1, "Entering the notch opens once, without repeated opens")
                detector.updateDragLocation(CGPoint(x: screen.midX, y: region.minY - 1))
                precondition(exits == 1)
                detector.updateDragLocation(nearNotch)
                precondition(entries == 2, "Dragging back to the notch still works")
                precondition(region.maxY == screen.maxY && region.height <= 40 && region.width == 225)
            }
        }
        print("Drag activation checks passed: ordinary drags stay closed; notch entry/re-entry works on offset displays and with hidden notch height.")
    }
}
