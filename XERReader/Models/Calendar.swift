import Foundation

struct WorkCalendar: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let projectId: String?
    let isDefault: Bool
    let hoursPerDay: Double
    let hoursPerWeek: Double
    let hoursPerMonth: Double
    let hoursPerYear: Double

    // Standard work week (Monday = 1, Sunday = 7)
    var workDays: Set<Int> = [1, 2, 3, 4, 5] // Mon-Fri default

    init(id: String, name: String, projectId: String? = nil, isDefault: Bool = false,
         hoursPerDay: Double = 8, hoursPerWeek: Double = 40,
         hoursPerMonth: Double = 172, hoursPerYear: Double = 2080) {
        self.id = id
        self.name = name
        self.projectId = projectId
        self.isDefault = isDefault
        self.hoursPerDay = hoursPerDay
        self.hoursPerWeek = hoursPerWeek
        self.hoursPerMonth = hoursPerMonth
        self.hoursPerYear = hoursPerYear
    }

    func isWorkDay(_ date: Date) -> Bool {
        let weekday = Foundation.Calendar.current.component(.weekday, from: date)
        // Convert from Sunday=1 to Monday=1 format
        let adjustedWeekday = weekday == 1 ? 7 : weekday - 1
        return workDays.contains(adjustedWeekday)
    }

    func workDaysBetween(_ start: Date, _ end: Date) -> Int {
        guard start < end else { return 0 }

        var count = 0
        var current = start
        let calendar = Foundation.Calendar.current

        while current < end {
            if isWorkDay(current) {
                count += 1
            }
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? end
        }

        return count
    }
}

struct CalendarException: Codable, Equatable {
    let calendarId: String
    let date: Date
    let hoursWorked: Double // 0 for holiday

    var isHoliday: Bool {
        hoursWorked == 0
    }
}
