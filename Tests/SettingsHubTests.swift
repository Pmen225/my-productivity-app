import Testing
@testable import Flowmap

/// Pure-data grouping for the Settings hub list (task 55). No SwiftData, no
/// View — every row must land in exactly one of the three founder-specified
/// groups, in the founder-specified order.
@Suite("Settings hub grouping")
struct SettingsHubTests {
    @Test("Every row appears in exactly one group, and every row is grouped")
    func everyRowGroupedExactlyOnce() {
        let allRows = SettingsHub.groups.flatMap(\.rows)
        #expect(allRows.count == SettingsHubRow.allCases.count)
        #expect(Set(allRows) == Set(SettingsHubRow.allCases))
    }

    @Test("Groups are Personalise, Alerts & connections, Data & about, in that order")
    func groupTitlesAndOrder() {
        #expect(SettingsHub.groups.map(\.title) == ["Personalise", "Alerts & connections", "Data & about"])
    }

    @Test("Personalise holds General then Focus Wheel")
    func personaliseMembership() {
        #expect(SettingsHub.groups[0].rows == [.general, .focusWheel])
    }

    @Test("Alerts & connections holds Sounds, Notifications, Calendar, Assistant")
    func alertsConnectionsMembership() {
        #expect(SettingsHub.groups[1].rows == [.sounds, .notifications, .calendar, .assistant])
    }

    @Test("Data & about holds Data then About")
    func dataAboutMembership() {
        #expect(SettingsHub.groups[2].rows == [.data, .about])
    }

    @Test("Every row has a non-empty title and symbol name")
    func rowsHaveTitleAndSymbol() {
        for row in SettingsHubRow.allCases {
            #expect(!row.title.isEmpty)
            #expect(!row.symbolName.isEmpty)
        }
    }
}
