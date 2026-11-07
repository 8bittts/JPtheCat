import AppKit
import JPtheCatCore
import SwiftUI
import UserNotifications

/// The settings face of the dashboard card. Tapping "Settings" in the top bar crossfades here;
/// "Dashboard" crossfades back to the main dashboard.
struct SettingsBackView: View {
  var model: DashboardViewModel
  var windowChrome: Bool = false
  var chrome: DashboardChromeState?
  var menuBarDisplayPresentation: MenuBarDisplayPresentationState? = nil
  var onToggleWindowPin: (() -> Void)?
  var onOpenAdvancedAnalytics: (() -> Void)?
  var onOpenLiveData: (() -> Void)?
  var onOpenThemes: (() -> Void)?
  var onClose: () -> Void
  @AppStorage(DockIconPreference.showDockIconKey) private var showDockIcon =
    DockIconPreference.defaultShowDockIcon
  // The alert toggles bind to the single source of truth; `UsageAlertCenter` reads the same keys.
  @ObservedObject private var settings = SettingsStore.shared
  @State private var launchAtLogin = LoginItem.isEnabled()
  @State private var launchAtLoginStatus = LoginItem.statusDescription()
  @State private var launchAtLoginError: String?
  // Live OS notification-authorization, so the banner row can warn when macOS is suppressing banners.
  @StateObject private var bannerAuth = BannerAuthorization()
  @State private var supportReport: String?
  @Environment(\.dashboardLayout) private var layout

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      topBar
      rule
      VStack(alignment: .leading, spacing: JPAppSpacing.settingsBodyY) {
        sections
      }
      .padding(.horizontal, JPAppSpacing.panelX).padding(.vertical, JPAppSpacing.settingsBodyY)
      Spacer(minLength: 0)
      footer
    }
    .frame(
      width: layout.width,
      alignment: .top
    )
    .background(JP.card)
    .sheet(
      isPresented: Binding(
        get: { supportReport != nil },
        set: { if !$0 { supportReport = nil } })
    ) {
      if let supportReport {
        SupportReportSheet(report: supportReport) {
          self.supportReport = nil
        }
      }
    }
    .onAppear {
      refreshLaunchAtLogin()
      bannerAuth.refresh()
    }
  }

  /// Both layouts show the same four sections in the same reading order.
  @ViewBuilder private var sections: some View {
    switch layout {
    case .oneColumn:
      generalSection
      liveDataSection
      alertsSection
      appearanceSection
    case .twoColumns:
      HStack(alignment: .top, spacing: DashboardSurfaceMetrics.selectorColumnGap) {
        VStack(alignment: .leading, spacing: JPAppSpacing.settingsBodyY) {
          generalSection
          liveDataSection
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        VStack(alignment: .leading, spacing: JPAppSpacing.settingsBodyY) {
          alertsSection
          appearanceSection
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }
  }

  // Settings sections retain their existing controls and bindings.
  private var generalSection: some View {
    section("General") {
      SettingsRow(
        icon: "menubar.rectangle",
        title: "Menu bar display",
        subtitle: menuBarDisplaySubtitle
      ) {
        settings.menuBarDisplayFormat =
          settings.menuBarDisplayFormat.next(providers: menuBarLimitProviders)
      }
      SettingsRow(
        icon: "arrow.clockwise",
        title: "Refresh rate",
        subtitle: "\(settings.refreshCadence.settingsTitle) — \(settings.refreshCadence.settingsSubtitle)"
      ) {
        settings.refreshCadence = settings.refreshCadence.next
      }
      SettingsToggleRow(
        icon: "macwindow",
        title: "Show Dock icon",
        subtitle: showDockIcon
          ? "Keep JP the Cat in the Dock and app switcher"
          : "Menu-bar only",
        isOn: $showDockIcon,
        onChange: { DockIconPreference.apply(showDockIcon: $0) })
      SettingsToggleRow(
        icon: "power.circle",
        title: "Launch at login",
        subtitle: launchAtLoginSubtitle,
        isOn: Binding(
          get: { launchAtLogin },
          set: { requested in
            launchAtLoginError = LoginItem.failureReason(settingEnabled: requested)
            launchAtLogin = LoginItem.isEnabled()
            launchAtLoginStatus = LoginItem.statusDescription()
          }))
      // Sparkle owns + persists this flag; bind straight to it (never mirror in SettingsStore).
      // Gated on `isConfigured` so dev builds with no feed don't show a dead toggle.
      if Updater.isConfigured {
        SettingsToggleRow(
          icon: "arrow.down.circle",
          title: "Automatic updates",
          subtitle: "Check for new versions automatically",
          isOn: Binding(
            get: { Updater.shared.automaticallyChecksForUpdates },
            set: { Updater.shared.automaticallyChecksForUpdates = $0 }))
      }
      SettingsRow(
        icon: "lifepreserver",
        title: "Support report",
        subtitle: "Send a redacted report — no prompts or code leave your Mac"
      ) {
        openSupportReport()
      }
      SettingsRow(
        icon: "chevron.left.forwardslash.chevron.right",
        title: "Open source",
        subtitle: "MIT licensed — read the code and contribute on GitHub"
      ) {
        Self.open(Self.repositoryURL)
      }
    }
  }

  private var liveDataSection: some View {
    section("Live data") {
      SettingsRow(
        icon: "dot.radiowaves.up.forward",
        title: "Providers & live limits",
        subtitle: "Choose which providers show and enable official limits"
      ) {
        onOpenLiveData?()
      }
    }
  }

  private var alertsSection: some View {
    section("Alerts") {
      SettingsToggleRow(
        icon: "bell", title: "Usage alerts at 80%",
        subtitle: "Watch all provider windows",
        isOn: $settings.usageAlertsEnabled,
        onChange: { _ in
          UsageAlertCenter.shared.requestBannerAuthorizationIfNeeded()
          bannerAuth.refresh()
        })
      SettingsToggleRow(
        icon: "app.badge", title: "Show notification banner",
        subtitle: bannerSubtitle,
        isOn: $settings.alertBannerEnabled,
        onChange: { _ in
          UsageAlertCenter.shared.requestBannerAuthorizationIfNeeded()
          bannerAuth.refresh()
        })
      // OS-level denial: the user wants banners but macOS is suppressing them — surface a route to
      // System Settings instead of silently no-op'ing. (Meow-only users never see this.)
      if showBannerDeniedAffordance {
        SettingsRow(
          icon: "exclamationmark.triangle",
          title: "Turn on in System Settings",
          subtitle: "macOS is set to hide JP the Cat's banners",
          destructive: true
        ) {
          SettingsBackView.open(
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        }
      }
      SettingsToggleRow(
        icon: "speaker.wave.2", title: "Meow on alerts",
        subtitle: "JP meows with each alert", isOn: $settings.alertSoundEnabled)
      SettingsToggleRow(
        icon: "speaker.wave.1", title: "Interactive sounds",
        subtitle: "Allow JP's meows and UI sounds",
        isOn: $settings.interactiveSoundsEnabled)
      SettingsJPActionRow(title: "Test meow", subtitle: "Tap JP to hear her roar!") {
        // Always fire: `playTestMeowFeedback` posts the banner unconditionally and only the MEOW
        // is gated on interactive sounds. Gating the whole call on the sound toggle used to swallow
        // the notification when sounds were off.
        UsageAlertCenter.shared.playTestMeowFeedback()
      }
    }
  }

  private var appearanceSection: some View {
    section("Appearance") {
      ThemePickerRow(onOpenThemes: onOpenThemes)
    }
  }

  // The banner row's subtitle folds in the OS-denial warning when macOS is suppressing banners.
  private var bannerSubtitle: String {
    if showBannerDeniedAffordance { return "Banner on, but macOS is hiding it" }
    return settings.alertBannerEnabled ? "Pop a macOS banner as you near a limit" : "Off — meow only, no banner"
  }

  // Show the "Turn on in System Settings" route only when the user wants banners (master + banner on)
  // AND macOS will silently drop them — either notifications are denied OR the alert style is "None"
  // while still authorized. Otherwise the banner just silently never appears.
  private var showBannerDeniedAffordance: Bool {
    UsageAlertCenter.bannerDenialWarrants(
      authorizationStatus: bannerAuth.status,
      alertStyle: bannerAuth.alertStyle,
      usageEnabled: settings.usageAlertsEnabled,
      bannerEnabled: settings.alertBannerEnabled)
  }

  // Live limit-bearing providers, in dashboard order, whose windows become dedicated
  // Total + <provider> <window> / <provider> <window> entries. Derived from the same rows the pill
  // reads, so adding a provider or another live window extends the picker with no further wiring.
  private var menuBarLimitProviders: [MenuBarLimitProvider] {
    availableMenuBarLimitProviders(from: model.state.rows)
  }

  private var menuBarDisplaySubtitle: String {
    let title = menuBarDisplayPresentation?.title ?? settings.menuBarDisplayFormat.settingsTitle
    let subtitle = menuBarDisplayPresentation?.subtitle ?? settings.menuBarDisplayFormat.settingsSubtitle
    let prefix = settings.menuBarDisplayFormat.isRotating ? "Rotating: " : ""
    return "\(prefix)\(title) — \(subtitle)"
  }

  private var rule: some View { Rectangle().fill(JP.line).frame(height: 1) }

  // MARK: Top bar — mirrors the front's 32pt bar; settings controls stay one compact cluster.

  private var topBar: some View {
    ChromeTitleRow(windowChrome: windowChrome) { settingsChromeControls }
  }

  // Refresh lives ONLY in the shared footer (both faces) — it never belongs in the top chrome row.
  private var settingsChromeControls: some View {
    HStack(spacing: JPAppSpacing.chromeControlGap) {
      RotationIndicatorLight(isRotating: settings.menuBarDisplayFormat.isRotating)
      MenuBarDisplayCycleButton(
        format: settings.menuBarDisplayFormat,
        renderedTitle: menuBarDisplayPresentation?.title,
        isEnabled: true
      ) {
        settings.menuBarDisplayFormat =
          settings.menuBarDisplayFormat.next(providers: menuBarLimitProviders)
      }
      DashboardLayoutButton(layout: layout) { settings.dashboardLayout = layout.next }
      if let chrome, let onToggleWindowPin {
        PinButton(isPinned: chrome.isPinned, action: onToggleWindowPin)
      }
      WidgetGalleryButton()
      DashboardBackLink(action: onClose)
    }
  }

  // MARK: Sections

  private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title.uppercased())
        .font(JPAppFont.eyebrowStrong)
        .foregroundStyle(JP.inkFaint)
      VStack(spacing: 1) { content() }
        .settingsWellBackground()
    }
  }

  /// Mirrors `DashboardView.footer` exactly (same icon set/order) so both faces show the identical
  /// footer — Refresh and the Advanced Analytics icon were previously missing here.
  private var footer: some View {
    DashboardCardFooter(
      leadingText: "Settings",
      onRefresh: { model.refresh() },
      onOpenAdvancedAnalytics: onOpenAdvancedAnalytics,
      onQuit: { NSApp.terminate(nil) },
      onOpenWebsite: { Self.open("https://jpthecat.com") },
      accessory: { UpdateStatusDot(currentVersion: appVersion) })
  }

  private var appVersion: String {
    let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    return "v\(short)"
  }

  private var launchAtLoginSubtitle: String {
    // A failed register/unregister wins the subtitle so the user sees the REAL reason, not a guess.
    if let launchAtLoginError { return "Couldn’t update: \(launchAtLoginError)" }
    switch launchAtLoginStatus {
    case "On":
      return "Starts automatically when you sign in"
    case "Off":
      return "Start JP the Cat automatically when you sign in"
    default:
      return launchAtLoginStatus
    }
  }

  private func openSupportReport() {
    let report = makeSupportReport()
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(report, forType: .string)
    supportReport = report
  }

  private func makeSupportReport() -> String {
    let info = Bundle.main.infoDictionary
    let input = SupportReportInput(
      appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
      buildNumber: info?["CFBundleVersion"] as? String ?? "unknown",
      installedAppVersion: installedApplicationVersion(),
      runningExecutablePath: Bundle.main.executableURL?.path,
      widgetAccess: WidgetSnapshotStore().readIfAvailable()?.access,
      macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      providerRows: model.state.rows,
      selectedDays: model.state.selectedDays)
    return SupportReport.make(input)
  }

  private func installedApplicationVersion() -> String? {
    let url = URL(fileURLWithPath: "/Applications/JPtheCat.app/Contents/Info.plist")
    guard let info = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
    let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
    let build = info["CFBundleVersion"] as? String ?? "unknown"
    return "\(version) (\(build))"
  }

  private func refreshLaunchAtLogin() {
    launchAtLogin = LoginItem.isEnabled()
    launchAtLoginStatus = LoginItem.statusDescription()
  }

  static let repositoryURL = "https://github.com/8bittts/JPtheCat"

  static func open(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }
    NSWorkspace.shared.open(url)
  }
}

/// Reads the live OS notification presentation state (authorization status + on-screen alert style) so
/// the "Show notification banner" row can warn when macOS is suppressing the banner — either
/// notifications are denied, or the alert style is "None" while still authorized. This is OS state, not
/// a stored setting — refreshed on appear and after the master/banner toggles flip.
@MainActor
private final class BannerAuthorization: ObservableObject {
  @Published private(set) var status: UNAuthorizationStatus = .notDetermined
  @Published private(set) var alertStyle: UNAlertStyle = .none

  func refresh() {
    Task { @MainActor in
      let presentation = await UsageAlertCenter.shared.currentBannerPresentation()
      status = presentation.status
      alertStyle = presentation.alertStyle
    }
  }
}

// MARK: - Support report sheet

private struct SupportReportSheet: View {
  let report: String
  let onClose: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var contactEmail = ""
  @State private var message = ""
  @State private var sending = false
  @State private var status: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        if let mark = AppResources.image(forResource: "jp-menubar") {
          Image(nsImage: mark)
            .resizable()
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous))
        }
        VStack(alignment: .leading, spacing: 3) {
          Text("Send a support report").font(JPAppFont.bodyStrong).foregroundStyle(JP.ink)
          Text("JP will email support@JPtheCat.com with a report.")
            .font(JPAppFont.body)
            .foregroundStyle(JP.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Your email (optional)").font(JPAppFont.eyebrowStrong).foregroundStyle(JP.inkFaint)
        TextField("you@example.com", text: $contactEmail)
          .textFieldStyle(.roundedBorder)
          .controlSize(.small)
          .font(JPAppFont.body)
          .disabled(sending)
        Text("Only add this if you want a reply. JP does not store it in the app.")
          .font(JPAppFont.micro)
          .foregroundStyle(JP.inkSoft)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("What happened? (optional)").font(JPAppFont.eyebrowStrong).foregroundStyle(JP.inkFaint)
        JPTextEditorField(
          placeholder: "Add context if you want.",
          text: $message,
          height: 96,
          disabled: sending,
          accessibilityLabel: "What happened")
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Redacted report").font(JPAppFont.eyebrowStrong).foregroundStyle(JP.inkFaint)
        ScrollView {
          Text(report)
            .font(JPAppFont.captionMono)
            .foregroundStyle(JP.inkSoft)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .frame(height: 150)
        .background(JP.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: JPAppRadius.well, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: JPAppRadius.well, style: .continuous)
            .strokeBorder(JP.line, lineWidth: 1))
      }

      if let status {
        Text(status)
          .font(JPAppFont.micro)
          .foregroundStyle(status == "Sent to support." ? JP.sage : JP.gingerDeep)
      }

      HStack {
        Button("Cancel") {
          dismiss()
          onClose()
        }
        .disabled(sending)
        Spacer()
        Button(sending ? "Sending…" : "Send") {
          send()
        }
        .buttonStyle(.borderedProminent)
        // Brand CTA is ginger-deep; the default prominent tint is system blue (root AGENTS.md).
        .tint(JP.gingerDeep)
        .disabled(sending)
      }
    }
    .padding(18)
    .frame(width: 460)
    .background(JP.card)
  }

  private func send() {
    sending = true
    status = nil
    Task {
      let result = await SupportReportClient.send(
        contactEmail: contactEmail,
        message: message,
        report: report)
      sending = false
      switch result {
      case .sent:
        status = "Sent to support."
        dismiss()
        onClose()
      case .invalidEmail:
        status = "That email doesn’t look right. Leave it blank or enter a valid address."
      case .failed:
        status = "Couldn’t send. The redacted report is still on your clipboard."
      }
    }
  }
}

private struct WidgetGalleryButton: View {
  // No inputs → would freeze at the launch palette without a theme dependency.
  // periphery:ignore
  @ObservedObject private var themeManager = ThemeManager.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false
  var body: some View {
    Button(action: {
      InteractiveSounds.shared.topClick()
      WidgetGalleryOpener.open()
    }) {
      Image(systemName: "square.grid.2x2")
        .font(JPAppFont.chromeIcon)
        .foregroundStyle(hovering ? JP.gingerDeep : JP.inkSoft)
        .frame(width: JPAppSpacing.chromeGlyphW, height: JPAppSpacing.chromeGlyphH)
        .frame(width: JPAppSpacing.chromeControlSize, height: JPAppSpacing.chromeControlSize)
        // [Regression fix] This was the ONLY chrome icon with an ALWAYS-ON background + border chip —
        // every sibling (`DashboardBackLink`, `PinButton`, `SettingsLink`) only shows a chip on hover
        // (`hovering ? JP.paper2.opacity(0.72) : .clear`, no permanent stroke).
        // The permanent chip made this one icon read as visibly darker/highlighted next to its plain
        // neighbors for no reason — matched the shared hover-only recipe exactly.
        .background(
          RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
            .fill(hovering ? JP.paper2.opacity(0.72) : .clear))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(reduceMotion ? nil : JPAppMotion.hover, value: hovering)
    .help("How to add the widget")
    .accessibilityLabel("How to add the widget")
  }
}

// MARK: - Provider opt-in rows (Claude/Grok live limits, Copilot/Cursor live data)

/// The install state EVERY provider opt-in row reduces to. Each capture type ships its own `State`
/// (some carry an associated `URL`), so the descriptor's `probeState` normalizes it here and ONE row
/// implementation drives every provider opt-in.
///
/// [Regression guard] One row, one `ProviderOptInIntent.resolve`, so copy-paste drift across the four
/// provider rows cannot recur.
enum ProviderOptInState: Equatable, Sendable {
  case active
  case installable
  case unavailable
}

/// What a toggle flip should DO, resolved purely from the requested value and the probed state.
/// Pure and internal so the "only `.installable` may reach the install alert; anything else offers
/// setup docs" rule is unit-testable ONCE for all four rows instead of re-asserted per copy.
enum ProviderOptInIntent: Equatable, Sendable {
  /// The switch already reads the requested value — SwiftUI re-sends the current value on rebuild.
  case ignore
  case confirmInstall
  /// No install path exists (`.unavailable`), so route to the manual setup docs and re-probe.
  case openSetupDocs
  case confirmUninstall

  static func resolve(
    requested: Bool, isOn: Bool, state: ProviderOptInState
  ) -> ProviderOptInIntent {
    guard requested != isOn else { return .ignore }
    guard requested else { return .confirmUninstall }
    return state == .installable ? .confirmInstall : .openSetupDocs
  }
}

/// The confirm-alert copy for one direction of one provider's opt-in. Every provider write is gated
/// behind one of these: never automatic, never on first run, always reversible from the same row.
struct ProviderOptInAlert {
  let title: String
  let message: String
  let confirmButton: String
}

/// Everything that differs between the provider opt-in rows: copy, brand chip, and the four
/// side-effecting closures. `reconcileStaleCapture` is deliberately OPTIONAL rather than a flag —
/// only Claude and Grok write a capture file that can outlive its install marker, and flattening that
/// branch into the rows that must NOT clear anything is exactly how the drift above started.
struct ProviderOptInDescriptor {
  let icon: String
  let providerMark: (resource: String, tintHex: String)
  /// `(state, captureIsFresh) -> String`. `captureIsFresh` refines DISPLAY only.
  let title: @Sendable (ProviderOptInState, Bool) -> String
  let subtitle: @Sendable (ProviderOptInState, Bool) -> String
  let installAlert: ProviderOptInAlert
  let uninstallAlert: ProviderOptInAlert
  let probeState: @Sendable () -> ProviderOptInState
  /// Whether the captured file currently reads FRESH. Display-only: it must never flip the switch, or
  /// a leftover file from a block removed outside this app reads as "still on" forever.
  var probeCaptureIsFresh: @Sendable () -> Bool = { false }
  /// Deletes the leftover capture file once the install marker's absence is confirmed. `nil` for
  /// providers that write no such file (Copilot, Cursor) — they must never clear anything.
  var reconcileStaleCapture: (@Sendable () -> Void)?
  let install: @Sendable () -> Void
  let uninstall: @Sendable () -> Void
}

extension ProviderOptInDescriptor: Sendable {}

/// One row for every provider opt-in: a `SettingsToggleRow` whose switch is driven by ONE ground-truth
/// signal (the install marker), an `.onAppear` re-probe, and a confirm-alert on both directions.
///
/// [HARD REQUIREMENT] This row OFFERS to configure a provider, so its call sites in
/// `LiveDataWindowContent` stay gated on a real local-presence check and the row stays hidden until the
/// tool is detected. The `.onAppear(perform: refresh)` below is the other half of that contract: an
/// install or uninstall performed outside the app is picked up the next time the window appears.
private struct ProviderOptInRow: View {
  var model: DashboardViewModel
  let descriptor: ProviderOptInDescriptor
  @State private var state: ProviderOptInState = .unavailable
  @State private var captureIsFresh = false

  var body: some View {
    SettingsToggleRow(
      icon: descriptor.icon,
      title: descriptor.title(state, captureIsFresh),
      subtitle: descriptor.subtitle(state, captureIsFresh),
      providerMark: descriptor.providerMark,
      isOn: Binding(
        get: { isInstalled },
        set: { requested in toggled(to: requested) }
      )
    )
    .onAppear(perform: refresh)
  }

  // The toggle's ON/OFF state is driven ENTIRELY by `state` (whether the capture block is actually
  // installed) — the ground truth for what this switch controls. `captureIsFresh` (whether captured
  // data is fresh) only refines the DISPLAY when the block is confirmed installed; it must never flip
  // the switch on its own, or a leftover file from a block removed by something OTHER than this app's
  // own uninstall flow reads as "still on" forever (see the reconciliation in `refresh()` below).
  private var isInstalled: Bool { state == .active }

  private func refresh() {
    state = descriptor.probeState()
    captureIsFresh = descriptor.probeCaptureIsFresh()
    // [Regression guard — "toggle doesn't stick"] The capture BLOCK can disappear without ever going
    // through this app's own uninstall flow — e.g. Claude Code regenerating/overwriting its own
    // statusline script on an update or reinit strips our marked block along with it. When that
    // happens, `state` correctly flips to NOT `.active` (marker gone), but the LAST captured
    // `claude-rate-limits.json` / `grok-rate-limits.json` stays on disk and reads "fresh" for up to 12h
    // (`ClaudeRateLimitStore.maxAgeSeconds`) regardless of why the marker vanished. Reconcile the
    // stale capture file once the marker's absence is confirmed, so every reader (row, gauge, pill)
    // agrees the feed is off.
    if let reconcileStaleCapture = descriptor.reconcileStaleCapture, state != .active, captureIsFresh {
      reconcileStaleCapture()
      captureIsFresh = false
      model.refresh(reindex: true)
    }
  }

  private func toggled(to requested: Bool) {
    switch ProviderOptInIntent.resolve(requested: requested, isOn: isInstalled, state: state) {
    case .ignore:
      return
    case .confirmInstall:
      confirm(descriptor.installAlert, then: descriptor.install)
    case .openSetupDocs:
      SettingsBackView.open("https://jpthecat.com")
      refresh()
    case .confirmUninstall:
      confirm(descriptor.uninstallAlert, then: descriptor.uninstall)
    }
  }

  private func confirm(_ copy: ProviderOptInAlert, then perform: () -> Void) {
    let alert = NSAlert(jpTitle: copy.title, jpMessage: copy.message)
    alert.addButton(withTitle: copy.confirmButton)
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    perform()
    refresh()
    // Re-derive the dashboard NOW, not on the next periodic poll (up to 5 minutes away on Relaxed
    // cadence) — every screen that reads this provider (selector row, provider detail, menu-bar
    // pill/tooltip, widget snapshot, alert windows) must pick the change up the instant the user flips
    // it, matching how `claudeProviderEnabled`/`codexProviderEnabled` already force an immediate
    // refresh via `handleSettingsChange`. Installing alone usually writes no data yet, but re-deriving
    // anyway keeps every screen consistent with the freshly-cleared/re-armed capture state.
    model.refresh(reindex: true)
  }
}

// MARK: - The provider opt-in descriptors

extension SettingsBackView {
  /// Opt-in setup for Claude's OFFICIAL 5h/weekly limits. Claude only exposes them through its
  /// statusline feed, so this appends a marked capture block to the user's statusline script — ONLY
  /// after an explicit, acknowledged tap. Never automatic on install. Never touches
  /// `~/.claude/settings.json` (it is READ only, to find the user's own script). Fully reversible.
  static let claudeLiveLimits = ProviderOptInDescriptor(
    // Claude's real brand-mark chip so it visually groups under the Claude Code enable row (title
    // conveys state).
    icon: "terminal",
    providerMark: ("provider-claude", JPAppColor.claudeTintHex),
    title: { state, captureIsFresh in
      switch state {
      case .active: return captureIsFresh ? "Claude live limits · on" : "Claude live limits · finishing setup"
      case .installable: return "Enable Claude live limits"
      case .unavailable: return "Claude live limits · manual setup"
      }
    },
    subtitle: { state, captureIsFresh in
      switch state {
      case .active:
        return captureIsFresh
          ? "Show official 5h + weekly stats"
          : "Installed — run Claude Code once to start the feed"
      case .installable: return "Show your real session/weekly % (edits your statusline)"
      case .unavailable: return "No statusline to hook — see setup docs"
      }
    },
    installAlert: ProviderOptInAlert(
      title: "Enable Claude live limits?",
      message: "Claude only reports its 5-hour and weekly usage limits through its statusline.\n\n"
        + "JP the Cat will append a small, clearly-marked block to your Claude statusline script that "
        + "writes those official numbers to a file it reads.\n\n"
        + "Your statusline output is unchanged, and you can turn this off here anytime. Nothing else "
        + "in your Claude config is touched.",
      confirmButton: "Enable"),
    uninstallAlert: ProviderOptInAlert(
      title: "Turn off Claude live limits?",
      message: "This removes the capture block from your statusline script. Claude's limit gauge will "
        + "disappear until you re-enable it.\n\nNothing else changes.",
      confirmButton: "Turn off"),
    probeState: {
      switch StatuslineCapture.state() {
      case .active:
        // Refresh an older capture block in place so an existing installer gains newly-forwarded
        // fields (per-model weekly windows) without having to toggle the feature off and on.
        StatuslineCapture.migrateIfNeeded()
        return .active
      case .installable: return .installable
      case .unavailable: return .unavailable
      }
    },
    probeCaptureIsFresh: { ClaudeRateLimitStore.isActive() },
    reconcileStaleCapture: { ClaudeRateLimitStore.clear() },
    install: { try? StatuslineCapture.install() },
    uninstall: {
      try? StatuslineCapture.uninstall()
      // Also clear the captured rate-limit file — otherwise it stays "fresh" for up to 12h
      // (`ClaudeRateLimitStore.maxAgeSeconds`) and the toggle springs back "on" the instant the
      // alert closes.
      ClaudeRateLimitStore.clear()
    })

  /// Opt-in setup for Grok Build's OFFICIAL SuperGrok / weekly credit %. Grok only fetches that
  /// number live and logs it to `~/.grok/logs/unified.jsonl` — this installs a marked global hook +
  /// capture script that scrapes those lines into `grok-rate-limits.json`. ONLY after an explicit,
  /// acknowledged tap. Never automatic. Never reads `auth.json`, never writes `config.toml`, never
  /// calls xAI. Fully reversible.
  /// Live Data rows for the OpenCode model-brand providers, in dashboard order. Names come from
  /// `OpenCodeBrand.displayName` (the catalog short name) so Settings, dashboard, and tray agree.
  struct BrandRow {
    let brand: OpenCodeBrand
    let icon: String
    let subtitle: String
  }

  static let brandRows: [BrandRow] = [
    BrandRow(brand: .nemotron, icon: "cpu", subtitle: "OpenCode on this Mac · list price when priced, tokens when free"),
    BrandRow(brand: .mimo, icon: "brain", subtitle: "OpenCode on this Mac · list price when priced, tokens when free"),
    BrandRow(brand: .bigPickle, icon: "leaf", subtitle: "OpenCode on this Mac · free smoke-test model"),
    BrandRow(brand: .deepseek, icon: "sparkle", subtitle: "OpenCode on this Mac · list price when priced, tokens when free"),
  ]

  static let grokLiveLimits = ProviderOptInDescriptor(
    // Grok's real brand-mark chip so it visually groups under the Grok enable row (title conveys state).
    icon: "sparkles",
    providerMark: ("provider-grok", JPAppColor.grokTintHex),
    title: { state, captureIsFresh in
      switch state {
      case .active: return captureIsFresh ? "Grok live limits · on" : "Grok live limits · finishing setup"
      case .installable: return "Enable Grok live limits"
      case .unavailable: return "Grok live limits · unavailable"
      }
    },
    subtitle: { state, captureIsFresh in
      switch state {
      case .active:
        return captureIsFresh
          ? "Show official SuperGrok weekly %"
          : "Installed — use Grok Build once to start the feed"
      case .installable: return "Show your real SuperGrok weekly % (adds a Grok hook)"
      case .unavailable: return "Install Grok Build to enable"
      }
    },
    installAlert: ProviderOptInAlert(
      title: "Enable Grok live limits?",
      message: "Grok Build only reports its SuperGrok weekly usage limit through a live billing "
        + "fetch (and a local debug log line).\n\n"
        + "JP the Cat will install a small, clearly-marked hook under ~/.grok/hooks/ that copies "
        + "that official percentage into a file it reads.\n\n"
        + "No prompts, no auth tokens, and no network calls from JP — only numbers Grok already "
        + "wrote locally. Turn this off here anytime.",
      confirmButton: "Enable"),
    uninstallAlert: ProviderOptInAlert(
      title: "Turn off Grok live limits?",
      message: "This removes the Grok hook and capture script. Grok's SuperGrok weekly gauge will "
        + "disappear until you re-enable it.\n\nNothing else changes.",
      confirmButton: "Turn off"),
    probeState: {
      let state = GrokRateLimitCapture.state()
      // `toggleIsOn` is Core's pure, unit-tested expression of the ONE-ground-truth-signal rule —
      // keep it as the authority for Grok's switch rather than re-deriving `.active` here.
      if GrokRateLimitCapture.toggleIsOn(state: state) { return .active }
      return state == .installable ? .installable : .unavailable
    },
    probeCaptureIsFresh: { GrokRateLimitStore.isActive() },
    // Same ground-truth rule as Claude: the install marker (hook+script), not a leftover capture
    // file, owns the toggle. If something else removed the hook, clear the stale file so the gauge
    // and switch agree the feed is off.
    reconcileStaleCapture: { GrokRateLimitStore.clear() },
    install: { try? GrokRateLimitCapture.install() },
    uninstall: {
      try? GrokRateLimitCapture.uninstall()
      GrokRateLimitStore.clear()
    })

  /// GitHub Copilot CLI has no `settings.json`-style config to write to (unlike Claude's statusline),
  /// so this is opt-in via the user's shell rc file instead — same consent/reversibility guarantee,
  /// different target. Enabling adds Copilot's token estimate to its own dashboard/widget view, but
  /// never to combined dollar totals or alerts. Copilot writes no capture file of its own, so it gets
  /// NO `reconcileStaleCapture` — there is nothing for it to clear.
  static let copilotLiveData = ProviderOptInDescriptor(
    // Copilot's real brand-mark chip (the same logo the dashboard selector shows) — this is the sole
    // Copilot row, so it carries the provider mark directly; the title conveys state.
    icon: "chevron.left.forwardslash.chevron.right",
    providerMark: ("provider-copilot", JPAppColor.copilotTintHex),
    title: { state, _ in
      switch state {
      case .active: return "Copilot CLI live data · on"
      case .installable: return "Enable Copilot CLI live data"
      case .unavailable: return "Copilot CLI live data · manual setup"
      }
    },
    // Copilot IS on the dashboard (its own row + sparkline) once this is on, unlike the earlier
    // terminal-only state — just excluded from aggregate dollar totals/alerts, which the
    // dashboard's own "estimate" badge + explainer already disclose. Keep this in sync with that.
    subtitle: { state, _ in
      switch state {
      case .active: return "On dashboard, not in totals"
      case .installable: return "Adds a dashboard row, not in totals"
      case .unavailable: return "No shell config detected"
      }
    },
    installAlert: ProviderOptInAlert(
      title: "Enable Copilot CLI live data?",
      message: "GitHub Copilot CLI only writes local usage data when its OpenTelemetry export is turned on.\n\n"
        + "JP the Cat will append a small, clearly-marked line to your shell config that enables it.\n\n"
        + "This only affects new shell sessions, and you can turn it off here anytime.\n\n"
        + "Nothing else in your shell config is touched.\n\n"
        + "Limitation: Copilot will show up on your dashboard with its own token estimate, but it's never "
        + "added to combined dollar totals or alerts — its token-estimate widget remains separate because its accounting isn't as precise as Claude/Codex/Grok's "
        + "official sources.",
      confirmButton: "Enable"),
    uninstallAlert: ProviderOptInAlert(
      title: "Turn off Copilot CLI live data?",
      message: "This removes the enablement line from your shell config. Copilot CLI will stop exporting "
        + "usage data for new sessions.\n\nNothing else changes.",
      confirmButton: "Turn off"),
    probeState: {
      switch CopilotOtelSetup.state() {
      case .active: return .active
      case .installable: return .installable
      case .unavailable: return .unavailable
      }
    },
    install: { try? CopilotOtelSetup.install() },
    uninstall: { try? CopilotOtelSetup.uninstall() })

  /// Cursor's designed `stop` hook exposes usage counts after an agent turn. Deliberately the same
  /// Live Data toggle/control contract as Copilot: explicit consent, reversible setup, an immediate
  /// dashboard refresh, token-only display, and no aggregate/alert contribution. Writes no capture
  /// file JP owns the freshness of, so it gets NO `reconcileStaleCapture` either.
  static let cursorLiveData = ProviderOptInDescriptor(
    icon: "cursorarrow.rays",
    providerMark: ("provider-cursor", JPAppColor.cursorTintHex),
    title: { state, _ in
      switch state {
      case .active: return "Cursor CLI live data · on"
      case .installable: return "Enable Cursor CLI live data"
      case .unavailable: return "Cursor CLI live data · unavailable"
      }
    },
    subtitle: { state, _ in
      switch state {
      case .active: return "On dashboard, not in totals"
      case .installable: return "Adds a token-only dashboard row"
      case .unavailable: return "Cursor CLI not detected"
      }
    },
    installAlert: ProviderOptInAlert(
      title: "Enable Cursor CLI live data?",
      message: "JP the Cat will add one clearly identified stop hook to Cursor's hooks.json and "
        + "store only local usage counts after new agent turns.\n\n"
        + "Prompts, responses, code, transcripts, and project paths are never stored.\n\n"
        + "Existing Cursor hooks are preserved, the hook always fails open, and you can remove it "
        + "here anytime.\n\n"
        + "Cursor appears as its own token estimate and is never added to dollar totals or alerts.",
      confirmButton: "Enable"),
    uninstallAlert: ProviderOptInAlert(
      title: "Turn off Cursor CLI live data?",
      message: "This removes only JP the Cat's Cursor stop hook and recorder script. Existing "
        + "Cursor hooks and captured usage counts stay untouched.",
      confirmButton: "Turn off"),
    probeState: {
      switch CursorHookSetup.state() {
      case .active: return .active
      case .installable: return .installable
      case .unavailable: return .unavailable
      }
    },
    install: { try? CursorHookSetup.install() },
    uninstall: { try? CursorHookSetup.uninstall() })

  /// One network opt-in for the shared Grok / Cursor / Grok Bot account service.
  static let grokPlanUsage = ProviderOptInDescriptor(
    icon: "gauge.with.dots.needle.50percent",
    providerMark: ("provider-grok", JPAppColor.grokTintHex),
    title: { state, _ in
      switch state {
      case .active: return "Grok plan usage · on"
      case .installable: return "Enable Grok plan usage"
      case .unavailable: return "Grok plan usage · unavailable"
      }
    },
    subtitle: { state, _ in state == .active ? "Weekly & billing-cycle pools · official" : "Use Cursor or Grok Bot's saved sign-in" },
    installAlert: ProviderOptInAlert(
      title: "Enable Grok plan usage?",
      message: "JP the Cat reads the sign-in Cursor or Grok Bot already saved on this Mac, using /usr/bin/security where required. It sends only that bearer token to api2.cursor.sh about every five minutes. No refresh tokens, prompts, code, transcripts, paths, or local usage are sent.\n\nOfficial percentages are separate from notional dollar totals. Turn this off here anytime.",
      confirmButton: "Enable"),
    uninstallAlert: ProviderOptInAlert(
      title: "Turn off Grok plan usage?",
      message: "Stops dashboard API calls and deletes unified and legacy plan caches. Local Grok and Cursor usage capture is unchanged.",
      confirmButton: "Turn off"),
    probeState: {
      if GrokPlanUsageStore.isEnabled() { return .active }
      return GrokPlanUsageStore.isSourcePresent() ? .installable : .unavailable
    },
    install: { try? GrokPlanUsageStore.enable() },
    uninstall: { GrokPlanUsageStore.disable() })

}

// MARK: - Live data window content

/// The scrollable body hosted by `LiveDataWindowController`. Re-hosts the former Settings → "Live data"
/// section VERBATIM (same rows, same styling, same behavior) in its own window so the provider list can
/// grow without competing with the intrinsic-height, no-scroll Settings face. Lives in this file so it
/// can reuse the private per-provider rows (`SettingsToggleRow`, and `ProviderOptInRow` driven by the
/// `ProviderOptInDescriptor`s on `SettingsBackView`). Observes `ThemeManager` so it re-themes live while open (a static leaf reading
/// `JP.*` would otherwise freeze at first-render theme — see the theme-freeze lesson in AGENTS.md).
struct LiveDataWindowContent: View {
  var model: DashboardViewModel
  @ObservedObject private var settings = SettingsStore.shared
  @ObservedObject private var themeManager = ThemeManager.shared
  @State private var copilotCLIDetected = CopilotOtelSetup.isCopilotCLIDetected()
  @State private var cursorCLIDetected = CursorHookSetup.isCursorCLIDetected()
  @State private var cursorSignInSourceDetected = CursorAuthToken.isSourcePresent()
  @State private var grokBuildDetected = GrokProvider.isGrokBuildDetected()
  @State private var grokBotDetected = GrokBotProvider.isGrokBotDetected()
  // ONE cached probe answers all seven OpenCode-derived rows (`OpenCodeDetection`); the rows used to
  // open seven read-only SQLite connections and run fourteen unindexed scans on every appearance.
  @State private var openCodeDetection = OpenCodeDetection.current(root: OpenCodeStorePaths.defaultRoot())
  @State private var museSparkDetected = MuseSparkProvider().isAvailable()

  var body: some View {
    // Fixed width, INTRINSIC height: the hosting controller uses `.preferredContentSize`, so the window
    // sizes exactly to this content (no dead space) and grows a row's worth taller as providers are
    // added — no `ScrollView` needed for today's list.
    VStack(alignment: .leading, spacing: 0) {
      chromeBar
      Rectangle().fill(JP.line).frame(height: 1)
      VStack(alignment: .leading, spacing: JPAppSpacing.settingsBodyY) {
        // No section eyebrow — the window's chrome title already reads "— Live data". Grouped by
        // provider so each provider's enable + its live-limit opt-in sit together: Claude, then Codex,
        // then Grok, then Muse Spark, then Copilot.
        sectionWell {
          SettingsToggleRow(
            icon: "terminal",
            title: "Claude Code",
            subtitle: settings.claudeProviderEnabled
              ? "In totals, widgets & alerts"
              : "Hidden from dashboard, widget & alerts",
            providerMark: ("provider-claude", JPAppColor.claudeTintHex),
            isOn: $settings.claudeProviderEnabled)
          ProviderOptInRow(model: model, descriptor: SettingsBackView.claudeLiveLimits)
          SettingsToggleRow(
            icon: "curlybraces",
            title: "Codex",
            subtitle: settings.codexProviderEnabled
              ? "In totals, widgets & alerts"
              : "Hidden from dashboard, widget & alerts",
            providerMark: ("provider-codex", JPAppColor.codexTintHex),
            isOn: $settings.codexProviderEnabled)
          if grokBuildDetected || grokBotDetected || cursorSignInSourceDetected || cursorCLIDetected {
            SettingsToggleRow(
              icon: "sparkles",
              title: "Grok",
              subtitle: settings.grokProviderEnabled
                ? "Build · Cursor · Grok Bot"
                : "Hidden from dashboard, widget & alerts",
              providerMark: ("provider-grok", JPAppColor.grokTintHex),
              isOn: $settings.grokProviderEnabled)
            if grokBuildDetected {
              ProviderOptInRow(model: model, descriptor: SettingsBackView.grokLiveLimits)
            }
            if cursorCLIDetected {
              ProviderOptInRow(model: model, descriptor: SettingsBackView.cursorLiveData)
            }
            if cursorSignInSourceDetected || grokBotDetected {
              ProviderOptInRow(model: model, descriptor: SettingsBackView.grokPlanUsage)
            }
          }
          if museSparkDetected {
            SettingsToggleRow(
              icon: "flame",
              title: "Muse Spark",
              subtitle: settings.museSparkProviderEnabled
                ? "OpenCode on this Mac · notional list price"
                : "Hidden from dashboard, widget & alerts",
              providerMark: ("provider-muse_spark", JPAppColor.museSparkTintHex),
              isOn: $settings.museSparkProviderEnabled)
          }
          ForEach(SettingsBackView.brandRows, id: \.brand) { row in
            if openCodeDetection.brands.contains(row.brand) {
              SettingsToggleRow(
                icon: row.icon,
                title: row.brand.displayName,
                subtitle: settings.isBrandEnabled(row.brand)
                  ? row.subtitle
                  : "Hidden from dashboard, widget & alerts",
                providerMark: ("provider-\(row.brand.id.rawValue)", JPAppColor.tintHex(for: row.brand.id)),
                isOn: Binding(
                  get: { settings.isBrandEnabled(row.brand) },
                  set: { settings.setBrandEnabled(row.brand, $0) }))
            }
          }
          if openCodeDetection.zen {
            SettingsToggleRow(
              icon: "wand.and.stars",
              title: "OpenCode Zen",
              subtitle: settings.openCodeZenProviderEnabled
                ? "Gateway view, not in totals · excluded from combined totals"
                : "Hidden from dashboard & alerts",
              providerMark: ("provider-opencode", JPAppColor.openCodeZenTintHex),
              isOn: $settings.openCodeZenProviderEnabled)
          }
          if openCodeDetection.go {
            SettingsToggleRow(
              icon: "gauge.with.dots.needle.33percent",
              title: "OpenCode Go",
              subtitle: settings.openCodeGoProviderEnabled
                ? "Gateway view, not in totals · 5-hour & weekly usage vs cap"
                : "Hidden from dashboard & alerts",
              providerMark: ("provider-opencodego", JPAppColor.openCodeGoTintHex),
              isOn: $settings.openCodeGoProviderEnabled)
          }
          if copilotCLIDetected {
            ProviderOptInRow(model: model, descriptor: SettingsBackView.copilotLiveData)
          }

        }
      }
      .padding(.horizontal, JPAppSpacing.panelX)
      .padding(.vertical, JPAppSpacing.settingsBodyY)
    }
    .frame(width: JPAppSpacing.liveDataWindowW, alignment: .top)
    .background(JP.card)
    .onAppear {
      copilotCLIDetected = CopilotOtelSetup.isCopilotCLIDetected()
      cursorCLIDetected = CursorHookSetup.isCursorCLIDetected()
      cursorSignInSourceDetected = CursorAuthToken.isSourcePresent()
      grokBuildDetected = GrokProvider.isGrokBuildDetected()
      grokBotDetected = GrokBotProvider.isGrokBotDetected()
      openCodeDetection = OpenCodeDetection.current(root: OpenCodeStorePaths.defaultRoot())
      museSparkDetected = MuseSparkProvider().isAvailable()
    }
  }

  /// `JP the Cat 🐾 — Live data` drawn inline with the traffic lights (the window sets
  /// `safeAreaRegions = []`), mirroring `AdvancedAnalyticsWindow`'s `chromeBar`.
  private var chromeBar: some View {
    ChromeTitleRow(subtitle: "— Live data")
  }

  /// The same boxed "well" styling `SettingsBackView.section(_:)` uses, minus the section eyebrow (the
  /// window chrome title already says "Live data"). Replicated here because `section(_:)` is a method on
  /// the settings view.
  @ViewBuilder
  private func sectionWell(@ViewBuilder _ content: () -> some View) -> some View {
    VStack(spacing: 1) { content() }
      .settingsWellBackground()
  }
}

private extension View {
  /// The boxed "settings well" surface — translucent paper fill + hairline stroke — shared by the
  /// Settings `section(_:)` groups and the Live data window's `sectionWell`. One definition so the two
  /// (previously hand-copied, per the old inline comment) can't drift.
  func settingsWellBackground() -> some View {
    background(
      JP.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: JPAppRadius.well, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: JPAppRadius.well, style: .continuous)
        .strokeBorder(JP.line.opacity(0.85), lineWidth: 0.5))
  }
}

// MARK: - Rows

/// A small status dot at the end of the settings chrome cluster. Green (`JP.sage`) when the app is
/// up to date, deep ginger (`JP.gingerDeep`) when the feed reports a newer build — honey is
/// only 1.73:1 on paper (fails WCAG), so it must not be used for this dot. Clicking runs a real
/// update check so the user can install. In dev builds (no Sparkle feed) it stays a static green dot.
/// Internal (not `private`) — shared with `DashboardView`'s footer, which mirrors this same accessory
/// so both faces show the update indicator, not just Settings.
struct UpdateStatusDot: View {
  let currentVersion: String

  var body: some View {
    if Updater.isConfigured {
      ConfiguredUpdateDot(updater: Updater.shared, currentVersion: currentVersion)
    } else {
      UpdateDotButton(
        available: false,
        helpText: "\(currentVersion) · up to date",
        accessibilityText: "Version \(currentVersion), up to date",
        action: {})
    }
  }
}

private struct ConfiguredUpdateDot: View {
  @ObservedObject var updater: Updater
  let currentVersion: String

  private var helpText: String {
    if updater.updateAvailable {
      let latest = updater.latestVersion.map { " (v\($0))" } ?? ""
      return "Update available\(latest) — click to install"
    }
    return "\(currentVersion) · up to date — click to check"
  }

  private var accessibilityText: String {
    updater.updateAvailable
      ? "Update available, click to install" : "Version \(currentVersion), up to date"
  }

  var body: some View {
    UpdateDotButton(
      available: updater.updateAvailable,
      helpText: helpText,
      accessibilityText: accessibilityText,
      action: { updater.checkForUpdates() }
    )
    .onAppear { updater.checkForUpdatesInBackground() }
  }
}

private struct UpdateDotButton: View {
  let available: Bool
  let helpText: String
  let accessibilityText: String
  let action: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false

  var body: some View {
    Button(action: { InteractiveSounds.shared.bottomClick(); action() }) {
      // gingerDeep (5.2:1 on paper) not honey (1.73:1, near-invisible) for the
      // attention state; VoiceOver also gets the state via accessibilityText.
      Circle()
        .fill(available ? JP.gingerDeep : JP.sage)
        .frame(width: 9, height: 9)
        .overlay(
          Circle().strokeBorder(JP.ink.opacity(0.12), lineWidth: 0.5)
        )
        .scaleEffect(hovering && !reduceMotion ? 1.18 : 1)
        // 18×18 — matches every other footer icon's hit target (`DashboardFooterActionButton`,
        // `AdvancedAnalyticsFooterButton`) so footer icon spacing reads even; `chromeControlSize` (26)
        // is a TOP-chrome-row size, this is the only usage of this view and it's footer-only.
        .frame(width: JPAppSpacing.footerIconBox, height: JPAppSpacing.footerIconBox)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .help(helpText)
    .accessibilityLabel(accessibilityText)
  }
}

private struct DashboardBackLink: View {
  let action: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false

  var body: some View {
    Button(action: { InteractiveSounds.shared.topClick(); action() }) {
      Image(systemName: "gauge.medium")
        .font(JPAppFont.chromeIcon)
        .foregroundStyle(hovering ? JP.gingerDeep : JP.inkSoft)
        .frame(width: JPAppSpacing.chromeGlyphW, height: JPAppSpacing.chromeGlyphH)
        .frame(width: JPAppSpacing.chromeControlSize, height: JPAppSpacing.chromeControlSize)
        .background(
          RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
            .fill(hovering ? JP.paper2.opacity(0.72) : .clear)
        )
        .overlay(
          RoundedRectangle(cornerRadius: JPAppRadius.controlChip, style: .continuous)
            .strokeBorder(hovering ? JP.lineStrong.opacity(0.95) : .clear, lineWidth: 1))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(reduceMotion ? nil : JPAppMotion.hover, value: hovering)
    .help("Back to dashboard")
    .accessibilityLabel("Back to dashboard")
  }
}

private struct SettingsRow: View {
  let icon: String
  let title: String
  var subtitle: String?
  var destructive: Bool = false
  let action: () -> Void
  // Re-render on theme change so global JP.* reads re-resolve.
  // periphery:ignore
  @ObservedObject private var themeManager = ThemeManager.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false

  var body: some View {
    Button(action: { InteractiveSounds.shared.topClick(); action() }) {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .font(JPAppFont.settingsIcon)
          .foregroundStyle(destructive ? JP.gingerDeep : JP.inkSoft)
          .frame(width: 18)
        VStack(alignment: .leading, spacing: 1) {
          Text(title)
            .font(JPAppFont.bodyStrong)
            .foregroundStyle(destructive ? JP.gingerDeep : JP.ink)
          if let subtitle {
            Text(subtitle).font(JPAppFont.caption).foregroundStyle(JP.inkFaint)
              .lineLimit(1).minimumScaleFactor(0.8)
          }
        }
        Spacer(minLength: 4)
        Image(systemName: "chevron.right").font(JPAppFont.chevron).foregroundStyle(JP.inkFaint)
      }
      .padding(.horizontal, JPAppSpacing.settingsRowX).padding(.vertical, JPAppSpacing.settingsRowY)
      .contentShape(Rectangle())
      .background(hovering ? JP.paper2.opacity(0.7) : .clear)
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(reduceMotion ? nil : JPAppMotion.hover, value: hovering)
    .accessibilityLabel(title)
    // The subtitle carries the live selection on cycle rows ("Menu bar display" → "Total + Claude …",
    // "Refresh rate" → "Balanced …"). Expose it as the value so VoiceOver speaks the current state and
    // what changed on each tap — a bare label(title) left screen-reader users cycling blind.
    .accessibilityValue(subtitle ?? "")
  }
}

private struct SettingsJPActionRow: View {
  let title: String
  var subtitle: String?
  let action: () -> Void
  // periphery:ignore - intentional theme dependency for static JP.* reads.
  @ObservedObject private var themeManager = ThemeManager.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "play.circle")
        .font(JPAppFont.settingsIcon)
        .foregroundStyle(JP.inkSoft)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(JPAppFont.bodyStrong).foregroundStyle(JP.ink)
        if let subtitle {
          Text(subtitle).font(JPAppFont.caption).foregroundStyle(JP.inkFaint)
            .lineLimit(1).minimumScaleFactor(0.8)
        }
      }
      Spacer(minLength: 4)
      Button(action: action) {
        Group {
          if let mark = AppResources.image(forResource: "jp-menubar") {
            Image(nsImage: mark).resizable().interpolation(.high)
          } else {
            Image(systemName: "pawprint.fill").foregroundStyle(JP.gingerDeep)
          }
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
        .overlay(Circle().stroke(JP.lineStrong.opacity(0.65), lineWidth: 1))
        .shadow(color: JP.ink.opacity(0.08), radius: 2, y: 1)
      }
      .buttonStyle(.plain)
      .help("Test JP's meow")
      .accessibilityLabel("Test meow")
    }
    .padding(.horizontal, JPAppSpacing.settingsRowX).padding(.vertical, JPAppSpacing.settingsRowY)
    .contentShape(Rectangle())
    .background(hovering ? JP.paper2.opacity(0.7) : .clear)
    .onHover { hovering = $0 }
    .animation(reduceMotion ? nil : JPAppMotion.hover, value: hovering)
  }
}

/// A settings row with a trailing switch (mirrors `SettingsRow` layout). `onChange` fires after the
/// bound value flips so callers can act (e.g. request notification authorization).
private struct SettingsToggleRow: View {
  let icon: String
  let title: String
  var subtitle: String?
  // When set, render the provider's real brand-mark chip (white `provider-*.svg` glyph on the brand
  // tint) instead of the SF Symbol `icon` — used by the Live Data window rows so they match the
  // dashboard selector's provider chips. `nil` (the default) keeps the plain SF Symbol for every other
  // Settings toggle.
  var providerMark: (resource: String, tintHex: String)? = nil
  @Binding var isOn: Bool
  var onChange: (Bool) -> Void = { _ in }
  // Re-render on theme change so global JP.* reads re-resolve.
  // periphery:ignore
  @ObservedObject private var themeManager = ThemeManager.shared

  var body: some View {
    HStack(spacing: 10) {
      if let providerMark {
        AnalyticsProviderMark(resourceName: providerMark.resource, tintHex: providerMark.tintHex)
          .accessibilityHidden(true)
      } else {
        Image(systemName: icon)
          .font(JPAppFont.settingsIcon).foregroundStyle(JP.inkSoft).frame(width: 18)
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(JPAppFont.bodyStrong).foregroundStyle(JP.ink)
        if let subtitle {
          Text(subtitle).font(JPAppFont.caption).foregroundStyle(JP.inkFaint)
            .lineLimit(1).minimumScaleFactor(0.8)
        }
      }
      // Icon + title/subtitle are decorative here: the Toggle below carries the title (label),
      // subtitle (hint), and On/Off (value), so hiding these stops VoiceOver reading the title twice.
      .accessibilityHidden(true)
      Spacer(minLength: 4)
      Toggle(isOn: $isOn) {
        EmptyView()
      }
      .labelsHidden()
      .toggleStyle(.switch)
      .controlSize(.regular)
      .tint(JP.ginger)
      .frame(width: JPAppSpacing.settingsSwitchSlotWidth, alignment: .trailing)
      .accessibilityLabel(title)
      .accessibilityValue(isOn ? "On" : "Off")
      .accessibilityHint(subtitle ?? "")
      .onChange(of: isOn) { _, newValue in
        InteractiveSounds.shared.toggle(newValue)
        onChange(newValue)
      }
    }
    .padding(.horizontal, JPAppSpacing.settingsRowX).padding(.vertical, JPAppSpacing.settingsRowY)
    .contentShape(Rectangle())
  }
}
