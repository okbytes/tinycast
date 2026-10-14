import Foundation

@main
struct PinSlotsTest {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // Ten digit keys is the ceiling: there is no ⌘10, so the eleventh pin gets no chord.
        check("ten slots", PinSlots.digits.count == 10)
        check("no digit repeats", Set(PinSlots.digits).count == PinSlots.digits.count)

        check("⌘1 is the first pin", PinSlots.index(for: "1") == 0)
        check("⌘9 is the ninth", PinSlots.index(for: "9") == 8)
        check("⌘0 is the tenth, not the first", PinSlots.index(for: "0") == 9)
        check("a letter is not a slot", PinSlots.index(for: "a") == nil)

        let numberRowKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
        for (index, keyCode) in numberRowKeyCodes.enumerated() {
            check(
                "physical number-row keycode \(keyCode) maps to slot \(index)",
                PinSlots.index(forKeyCode: keyCode) == index)
        }
        check("unknown keycode is not a slot", PinSlots.index(forKeyCode: 0) == nil)

        check("the first row shows 1", PinSlots.digit(at: 0) == "1")
        check("the tenth row shows 0", PinSlots.digit(at: 9) == "0")
        check("the eleventh row shows nothing", PinSlots.digit(at: 10) == nil)
        check("a negative index shows nothing", PinSlots.digit(at: -1) == nil)

        // The row overlay and the key handler must agree, or a row advertises another's chord.
        for index in PinSlots.digits.indices {
            guard let digit = PinSlots.digit(at: index) else {
                check("slot \(index) has a digit", false)
                continue
            }
            check("slot \(index) round-trips", PinSlots.index(for: digit) == index)
        }

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) failed")
        if failures > 0 { exit(1) }
    }
}
