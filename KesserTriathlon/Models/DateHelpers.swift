import Foundation

extension Calendar {
    /// Deutscher Kalender, Woche beginnt am Montag.
    static let de: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "de_DE")
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        cal.timeZone = .current
        return cal
    }()
}

extension Date {
    var startOfDay: Date { Calendar.de.startOfDay(for: self) }

    var startOfWeek: Date {
        let comps = Calendar.de.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return Calendar.de.date(from: comps)?.startOfDay ?? startOfDay
    }

    /// 0 = Montag … 6 = Sonntag
    var weekdayIndex: Int {
        (Calendar.de.component(.weekday, from: self) + 5) % 7
    }

    var weekOfYear: Int { Calendar.de.component(.weekOfYear, from: self) }

    func adding(days: Int) -> Date {
        Calendar.de.date(byAdding: .day, value: days, to: self) ?? self
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.de.isDate(self, inSameDayAs: other)
    }

    var isToday: Bool { Calendar.de.isDateInToday(self) }

    func days(until other: Date) -> Int {
        Calendar.de.dateComponents([.day], from: startOfDay, to: other.startOfDay).day ?? 0
    }

    /// z. B. "Mo., 24. Nov."
    var shortDayText: String {
        formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "de_DE")))
    }

    /// z. B. "Montag"
    var weekdayName: String {
        formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "de_DE")))
    }

    var timeText: String {
        formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE")))
    }
}

enum Weekdays {
    static let short = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    static let long = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
}

func formatMinutes(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes) Min" }
    let h = minutes / 60, m = minutes % 60
    return m == 0 ? "\(h) h" : "\(h):\(String(format: "%02d", m)) h"
}
