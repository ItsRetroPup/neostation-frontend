import Foundation
import GameController

class GamepadsListener {
    var gamepads: [GCExtendedGamepad] = []
    var listener: ((Int, GCExtendedGamepad, GCControllerElement) -> Void)?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(joystickDidConnect),
            name: .GCControllerDidConnect,
            object: nil
        )

        // Controllers may already be connected before Flutter registers this
        // plugin. Notifications are not replayed for those devices, so attach
        // their handlers explicitly as well.
        for controller in GCController.controllers() {
            addGamepad(from: controller)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(joystickDidDisconnect),
            name: .GCControllerDidDisconnect,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
 
    @objc private func joystickDidConnect(notification: NSNotification) {
        if let controller = notification.object as? GCController {
            addGamepad(from: controller)
        }
    }

    private func addGamepad(from controller: GCController) {
        guard let gamepad = controller.extendedGamepad,
              !gamepads.contains(gamepad) else {
            return
        }

        gamepads.append(gamepad)
        let gamepadId = getAndSetPlayerId(of: gamepad)

        gamepad.valueChangedHandler = { gamepad, element in
            if let listener = self.listener {
                listener(gamepadId, gamepad, element)
            }
        }
    }
 
    @objc private func joystickDidDisconnect(notification: NSNotification) {
        if let controller = notification.object as? GCController {
            gamepads.removeAll(where: { $0 == controller.extendedGamepad })
        }
    }

    private func getAndSetPlayerId(of gamepad: GCExtendedGamepad) -> Int {
        let gamepadId = gamepads.firstIndex(of: gamepad) ?? -1
        gamepad.controller?.playerIndex = toPlayerIndex(index: gamepadId)
        return gamepadId
    }

    private func toPlayerIndex(index: Int) -> GCControllerPlayerIndex {
        switch index {
        case 0:
            return GCControllerPlayerIndex.index1
        case 1:
            return GCControllerPlayerIndex.index2
        case 2:
            return GCControllerPlayerIndex.index3
        case 3:
            return GCControllerPlayerIndex.index4
        default:
            return GCControllerPlayerIndex.indexUnset
        }
    }
}
