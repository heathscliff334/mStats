import Testing
@testable import mStatsKit

@Suite struct OverviewTabTests {
    @Test func enabledTabsPreservesFixedOrder() {
        let tabs = OverviewTab.enabledTabs(
            cpu: false, memory: true, disk: false, network: true,
            sensors: false, battery: true, ports: true,
            docker: true, dockerRunning: true, clipboard: true
        )
        #expect(tabs == [.memory, .network, .battery, .ports, .docker, .clipboard])
    }

    @Test func enabledTabsEmptyWhenNoneEnabled() {
        let tabs = OverviewTab.enabledTabs(
            cpu: false, memory: false, disk: false, network: false,
            sensors: false, battery: false, ports: false,
            docker: false, dockerRunning: false, clipboard: false
        )
        #expect(tabs.isEmpty)
    }

    @Test func dockerTabHiddenWhenEnabledButNotDetectedRunning() {
        let tabs = OverviewTab.enabledTabs(
            cpu: false, memory: false, disk: false, network: false,
            sensors: false, battery: false, ports: false,
            docker: true, dockerRunning: false, clipboard: false
        )
        #expect(tabs.isEmpty)
    }

    @Test func dockerTabShownWhenEnabledAndRunning() {
        let tabs = OverviewTab.enabledTabs(
            cpu: false, memory: false, disk: false, network: false,
            sensors: false, battery: false, ports: false,
            docker: true, dockerRunning: true, clipboard: false
        )
        #expect(tabs == [.docker])
    }

    @Test func resolveSelectionKeepsPreferredWhenStillEnabled() {
        let selection = OverviewTab.resolveSelection(preferred: .disk, enabled: [.cpu, .disk, .ports])
        #expect(selection == .disk)
    }

    @Test func resolveSelectionFallsBackToFirstWhenPreferredDisabled() {
        let selection = OverviewTab.resolveSelection(preferred: .disk, enabled: [.cpu, .ports])
        #expect(selection == .cpu)
    }

    @Test func resolveSelectionNilWhenNothingEnabled() {
        let selection = OverviewTab.resolveSelection(preferred: .disk, enabled: [])
        #expect(selection == nil)
    }

    @Test func resolveSelectionNilPreferredPicksFirst() {
        let selection = OverviewTab.resolveSelection(preferred: nil, enabled: [.memory, .battery])
        #expect(selection == .memory)
    }
}
