import Foundation

/// Deadline labels format the civil day itself, rather than converting an instant.
enum DeadlinePresentation {
    static func short(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3 else { return day }
        return "\(parts[1])/\(parts[2])"
    }

    static func full(_ day: String) -> String {
        guard let date = CivilDay.displayDate(from: day) else { return day }
        let formatter = DateFormatter()
        formatter.calendar = CivilDay.calendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
