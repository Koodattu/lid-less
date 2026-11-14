import Foundation

public struct SessionSettings: Equatable {
    public static let durations: [TimeInterval] = [1_800, 3_600, 7_200, 28_800]
    public static let batteryFloors = [10, 15, 20, 25, 30, 40, 50]

    public let duration: TimeInterval
    public let batteryFloor: Int

    public init(duration: TimeInterval = 28_800, batteryFloor: Int = 15) {
        self.duration = Self.durations.contains(duration) ? duration : 28_800
        self.batteryFloor = Self.batteryFloors.contains(batteryFloor) ? batteryFloor : 15
    }
}
