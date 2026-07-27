import SwiftUI

/// Persists grouping mode for a query-backed `SmartView`.
///
/// User `TaskList`s already carry `groupingMode` as a stored property. Smart
/// views have no model of their own to store it on, so the selection is kept
/// in `UserDefaults` instead, one key per view, so switching Inbox to
/// "Priority" never touches Today's grouping.
@propertyWrapper
public struct SmartViewGrouping: DynamicProperty {
    @AppStorage private var raw: String

    public init(_ view: SmartView) {
        _raw = AppStorage(wrappedValue: GroupingMode.manual.rawValue, "smartViewGrouping.\(view.rawValue)")
    }

    public var wrappedValue: GroupingMode {
        get { GroupingMode(rawValue: raw) ?? .manual }
        nonmutating set { raw = newValue.rawValue }
    }
}
