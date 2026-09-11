import Observation

/// Lets code outside `CombinedOverviewView` (the AppDelegate global-hotkey
/// handler) force the panel to a specific tab before showing it — a plain
/// `@State` inside the view can't be set from the outside.
@Observable
@MainActor
public final class OverviewSelection {
    public var selectedTab: OverviewTab?

    public init(selectedTab: OverviewTab? = nil) {
        self.selectedTab = selectedTab
    }
}
