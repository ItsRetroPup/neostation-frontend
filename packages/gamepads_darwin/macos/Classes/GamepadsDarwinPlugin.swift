import Cocoa
import GameController
import FlutterMacOS

public class GamepadsDarwinPlugin: NSObject, FlutterPlugin {
    let channel: FlutterMethodChannel
    let gamepads = GamepadsListener()

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()

        self.gamepads.listener = onGamepadEvent
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "xyz.luan/gamepads", binaryMessenger: registrar.messenger)
        let instance = GamepadsDarwinPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "listGamepads":
            result(listGamepads())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func onGamepadEvent(gamepadId: Int, gamepad: GCExtendedGamepad, element: GCControllerElement) {
        for (key, value) in getValues(gamepad: gamepad, element: element) {
            let arguments: [String: Any] = [
                "gamepadId": String(gamepadId),
                "time": Int(getTimestamp(gamepad: gamepad)),
                "type": element.isAnalog ? "analog" : "button",
                "key": key,
                "value": value,
            ]
            channel.invokeMethod("onGamepadEvent", arguments: arguments)
        }
    }

    private func getValues(gamepad: GCExtendedGamepad, element: GCControllerElement) -> [(String, Float)] {
        if let element = element as? GCControllerButtonInput {
            // GameController gives the PlayStation Create and Options buttons
            // the same SF Symbol (`capsule.portrait`). Preserve the owning
            // control here so Dart can use Create as the Select chord modifier
            // without turning the Options button into Select as well.
            if #available(macOS 10.15, *) {
                if element == gamepad.buttonOptions {
                    return [("select", element.value)]
                }
                if element == gamepad.buttonMenu {
                    return [("start", element.value)]
                }
            }
            var button: String = "Unknown button"
            if #available(macOS 11.0, *) {
                if (element.sfSymbolsName != nil) {
                    button = element.sfSymbolsName!
                }
            }
            
            return [(button, element.value)]
        } else if let element = element as? GCControllerAxisInput {
            var axis: String = axisName(gamepad: gamepad, axis: element)
            if #available(macOS 11.0, *) {
                if (element.sfSymbolsName != nil) {
                    axis = element.sfSymbolsName!
                }
            }
            return [(axis, element.value)]
        } else if let element = element as? GCControllerDirectionPad {
            let directionPad = directionPadName(gamepad: gamepad, directionPad: element)
            return [
                ("\(directionPad)_x_axis", element.xAxis.value),
                ("\(directionPad)_y_axis", element.yAxis.value)
            ]
        } else {
            return []
        }
    }

    /// GCControllerAxisInput does not provide an SF Symbol name.  Name the
    /// axes from their owning control so Dart can distinguish the two sticks
    /// and the D-pad instead of receiving a shared "Unknown axis" key.
    private func axisName(gamepad: GCExtendedGamepad, axis: GCControllerAxisInput) -> String {
        if axis == gamepad.dpad.xAxis { return "dpad_x_axis" }
        if axis == gamepad.dpad.yAxis { return "dpad_y_axis" }
        if axis == gamepad.leftThumbstick.xAxis { return "left_thumbstick_x" }
        if axis == gamepad.leftThumbstick.yAxis { return "left_thumbstick_y" }
        if axis == gamepad.rightThumbstick.xAxis { return "right_thumbstick_x" }
        if axis == gamepad.rightThumbstick.yAxis { return "right_thumbstick_y" }
        return "unknown_axis"
    }

    private func directionPadName(gamepad: GCExtendedGamepad, directionPad: GCControllerDirectionPad) -> String {
        if directionPad == gamepad.dpad { return "dpad" }
        if directionPad == gamepad.leftThumbstick { return "left_thumbstick" }
        if directionPad == gamepad.rightThumbstick { return "right_thumbstick" }
        return "unknown_direction_pad"
    }
    
    private func getNameForElement(element: GCControllerElement) -> String? {
        if #available(macOS 11.0, *) {
            return element.sfSymbolsName
        } else {
            return nil
        }
    }

    private func getTimestamp(gamepad: GCExtendedGamepad) -> TimeInterval {
        if #available(macOS 11.0, *) {
            return gamepad.lastEventTimestamp
        } else {
            return Date().timeIntervalSince1970
        }
    }

    private func getName(gamepad: GCExtendedGamepad) -> String {
        if #available(macOS 11.0, *) {
            let device = gamepad.device
            return maybeConcat(device?.vendorName, device?.productCategory) ?? "Unknown device"
        } else {
            return "Unknown device"
        }
    }

    private func listGamepads() -> [[String: Any?]] {
        return gamepads.gamepads.enumerated().map { (index, gamepad) in
            [ "id": String(index), "name": getName(gamepad: gamepad) ]
        }
    }

    private func maybeConcat(_ string1: String?, _ string2: String) -> String {
        return maybeConcat(string1, string2)!
    }

    private func maybeConcat(_ strings: String?...) -> String? {
        let nonNull = strings.compactMap { $0 }
        if (nonNull.isEmpty) {
            return nil
        }
        return nonNull.joined(separator: " - ")
    }
}

extension Optional {
    func map<T>(_ closure: (Wrapped) -> T) -> T? {
        if let value = self {
            return closure(value)
        } else {
            return nil
        }
    }
}
