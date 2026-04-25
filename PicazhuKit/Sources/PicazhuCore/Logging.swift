import Foundation
import OSLog

public enum PicazhuLog {
    public static let subsystem = "com.picazhu.mac"
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let data = Logger(subsystem: subsystem, category: "data")
    public static let indexing = Logger(subsystem: subsystem, category: "indexing")
    public static let media = Logger(subsystem: subsystem, category: "media")
    public static let search = Logger(subsystem: subsystem, category: "search")
    public static let ai = Logger(subsystem: subsystem, category: "ai")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
