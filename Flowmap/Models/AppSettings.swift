import Foundation
import SwiftData

/// The single settings record for this user. API key *values* never live here —
/// only the provider and model identifiers. Keys stay in the Keychain.
@Model
public final class AppSettings {
    public var id: UUID = UUID()

    // Appearance
    public var appearanceRaw: String = AppearanceMode.system.rawValue
    /// The named theme the app is painted in. Raw string per the repo's
    /// enum-persistence convention, defaulted so older CloudKit records stay valid.
    public var themeRaw: String = FlowPalette.default.id
    public var accentToken: String = ColourToken.clay.rawValue
    /// Which typeface the app renders in. Defaults to the system face; the
    /// founder can switch to iA Writer in Settings → General.
    public var appFontRaw: String = AppFontChoice.system.rawValue
    /// 1 = Sunday, 2 = Monday, matching `Calendar.firstWeekday`.
    public var firstWeekday: Int = 2

    // Day shape
    public var workdayStartHour: Int = 8
    public var workdayStartMinute: Int = 0
    public var workdayEndHour: Int = 21
    public var workdayEndMinute: Int = 0
    public var defaultTaskMinutes: Int = 30
    public var defaultFreeFocusMinutes: Int = 30

    // Focus wheel
    public var wheelVisibilityRaw: String = WheelVisibility.two.rawValue
    public var wheelZoomStyleRaw: String = WheelZoomStyle.magnify.rawValue
    /// How far the close-up style is magnified about the pointer, 1…8. Settles
    /// where the pinch left it so the wheel is where you left it next session.
    public var wheelMagnifyFactor: Double = 1
    public var focusSoundEnabled: Bool = true
    public var focusTickEnabled: Bool = true
    public var focusHapticsEnabled: Bool = true
    public var autoStartNextTask: Bool = true

    // Focus voice coach
    /// Speaks task-start, time-left and wind-down announcements during focus.
    public var focusVoiceEnabled: Bool = true
    /// The chosen `AVSpeechSynthesisVoice.identifier`. Nil uses the system
    /// default for the current language.
    public var focusVoiceIdentifier: String?
    /// Curated style label shown in Settings. The identifier above remains
    /// optional so older records continue to use the system default safely.
    public var focusVoiceStyleRaw: String = FocusVoiceStyle.calm.rawValue
    /// Relative volume for spoken announcements — never the system volume.
    public var focusVoiceVolume: Double = 0.8

    // Notifications
    public var notifyFiveMinuteWarning: Bool = true
    public var notifyTaskStart: Bool = true
    public var notifyTaskEnd: Bool = true
    public var notifyCarryoverSummary: Bool = true

    // Auto-plan
    /// Requeued work always goes somewhere; this only chooses *where first*.
    public var requeuePrefersLaterToday: Bool = true
    public var autoPlanOnAppOpen: Bool = false
    /// Calendar day whose accepted plan is closed to spontaneous additions.
    /// Optional keeps older CloudKit records valid while the boundary is introduced.
    public var sealedPlanDay: Date? = nil
    /// The most recent sealed day for which the compulsory review was finished.
    public var lastRolloverReviewedDay: Date? = nil

    // Calendar
    public var calendarIntegrationEnabled: Bool = false
    /// EventKit calendar identifiers the user opted into showing.
    public var selectedCalendarIdentifiers: [String] = []
    public var writeBackCalendarIdentifier: String?
    public var writesFocusBlocksToCalendar: Bool = false

    // Google Calendar
    public var googleCalendarEnabled: Bool = false
    /// Google calendar ids the user opted into showing.
    public var selectedGoogleCalendarIdentifiers: [String] = []
    /// The signed-in account, shown in Settings so it is obvious whose calendar
    /// is being read. Never a credential — tokens live in the Keychain only.
    public var googleAccountLabel: String?
    /// OAuth client id for the installed-app flow. Public by design (the flow is
    /// PKCE, so there is no client secret), and per-install because each build
    /// signs in with its own Google Cloud project.
    public var googleOAuthClientID: String?

    // Assistant
    public var assistantProviderRaw: String = AssistantProvider.anthropic.rawValue
    public var assistantModel: String = AssistantProvider.anthropic.defaultModel

    // Gamification
    /// The single running XP total for this user. Level and progress are
    /// never stored — `GamificationService` derives them from this on every
    /// read, exactly as `Project.progress` derives from its tasks.
    public var totalXP: Int = 0
    /// The day the "day cleared" bonus was last awarded, so a reconciliation
    /// pass or a second device cannot award it twice for the same day.
    public var lastDayClearedAwardDay: Date?

    // Lifecycle
    public var hasCompletedOnboarding: Bool = false
    public var hasLoadedDemoData: Bool = false
    public var lastReconciliationAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init() {
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func touch(_ date: Date = Date()) { updatedAt = date }

    // MARK: - Computed accessors

    public var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue; touch() }
    }

    public var accent: ColourToken {
        get { ColourToken.token(accentToken) }
        set { accentToken = newValue.rawValue; touch() }
    }

    public var appFont: AppFontChoice {
        get { AppFontChoice(rawValue: appFontRaw) ?? .system }
        set {
            appFontRaw = newValue.rawValue
            // Keep the static tokens in lockstep wherever the choice is set —
            // the Settings picker and the demo seed's reset both rely on this.
            FlowFont.choice = newValue
            touch()
        }
    }

    public var wheelVisibility: WheelVisibility {
        get { WheelVisibility(rawValue: wheelVisibilityRaw) ?? .two }
        set { wheelVisibilityRaw = newValue.rawValue; touch() }
    }

    public var wheelZoomStyle: WheelZoomStyle {
        get { WheelZoomStyle(rawValue: wheelZoomStyleRaw) ?? .magnify }
        set { wheelZoomStyleRaw = newValue.rawValue; touch() }
    }

    public var focusVoiceStyle: FocusVoiceStyle {
        get { FocusVoiceStyle(rawValue: focusVoiceStyleRaw) ?? .calm }
        set { focusVoiceStyleRaw = newValue.rawValue; touch() }
    }

    public var assistantProvider: AssistantProvider {
        get { AssistantProvider(rawValue: assistantProviderRaw) ?? .anthropic }
        set {
            assistantProviderRaw = newValue.rawValue
            if !newValue.availableModels.contains(assistantModel) {
                assistantModel = newValue.defaultModel
            }
            touch()
        }
    }

    // MARK: - Day window

    /// Start of the working day on `date`, in the current calendar.
    public func workdayStart(on date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(
            bySettingHour: min(23, max(0, workdayStartHour)),
            minute: min(59, max(0, workdayStartMinute)),
            second: 0,
            of: date
        ) ?? calendar.startOfDay(for: date)
    }

    /// End of the working day on `date`. Always after the start.
    public func workdayEnd(on date: Date, calendar: Calendar = .current) -> Date {
        let end = calendar.date(
            bySettingHour: min(23, max(0, workdayEndHour)),
            minute: min(59, max(0, workdayEndMinute)),
            second: 0,
            of: date
        ) ?? calendar.startOfDay(for: date).addingTimeInterval(21 * 3600)
        let start = workdayStart(on: date, calendar: calendar)
        return end > start ? end : start.addingTimeInterval(3600)
    }

    public var workdayStartLabel: String {
        String(format: "%02d:%02d", workdayStartHour, workdayStartMinute)
    }

    public var workdayEndLabel: String {
        String(format: "%02d:%02d", workdayEndHour, workdayEndMinute)
    }
}
