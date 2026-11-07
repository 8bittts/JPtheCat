import AppKit
import SwiftUI

/// A named color theme — the foundation for the theme system. **Adding a theme is a data
/// change, not a code change:** append a `JPTheme` to `JPTheme.all` (mark `inMoreThemes: true` to list it under
/// "More themes") and every UI surface picks it up, because all colors resolve from the *active* theme via
/// `JPAppColor`. Palette roles mirror `web/app/globals.css` so the app and site stay one product.
struct JPTheme: Identifiable, Equatable {
  let id: String  // stable key: persisted
  let name: String  // display name
  /// Drives `NSApp.appearance` (.darkAqua / .aqua) so the NSMenu, window chrome, and Sparkle dialogs
  /// match the card instead of following the system.
  let isDark: Bool
  /// Inline themes show directly in Settings; the rest live behind the "More themes" window. All are free.
  let inMoreThemes: Bool

  // Palette — hex strings are the single source (Color + NSColor derived on demand).
  let paper, paper2, card, ink, inkSoft, inkFaint, line, lineStrong: String
  /// Empty-meter/track groove. Distinct from `card` on both themes so bar/gauge tracks stay visible
  /// on the dark card (where `paper2` collapses to the card color).
  let track: String
  let ginger, gingerDeep, sage, sageSoft, honey, creamDeep, gold, cta, ctaDeep, coral: String
  /// Text-legible deep green for a label sitting on a translucent sage chip (the "official" gauge
  /// badge) — plain `sage` is only ~3.95:1 on the light sage chip.
  let sageDeep: String
  /// The label color drawn ON the `[cta, ctaDeep]` accent button. Flips per theme because the CTA
  /// gradient is dark on light themes (white text) and bright on dark themes (ink text) — so white is
  /// never painted on a bright accent (the old `.white`-on-ginger CTA failed AA on both themes).
  let ctaText: String
}

extension JPTheme {
  /// Sunlit Ledger — the warm daylight default (free). Mirrors the shipped web palette exactly.
  static let sunlit = JPTheme(
    id: "sunlit", name: "Sunlit Ledger", isDark: false, inMoreThemes: false,
    paper: "FAF6EC", paper2: "F4ECDA", card: "FFFDF7", ink: "221D15", inkSoft: "6C6253",
    inkFaint: "756A55", line: "E8DDC7", lineStrong: "D9CCAE", track: "ECDCBD",
    ginger: "DF7A2E", gingerDeep: "A84D14", sage: "3C7852", sageSoft: "6FAE84",
    honey: "EDB454", creamDeep: "ECDCBD", gold: "FDCD2D", cta: "A84F16", ctaDeep: "8F420E",
    coral: "C1422A", sageDeep: "2E5E40", ctaText: "FFFFFF")

  /// Midnight Ledger — warm-charcoal dark counterpart (free). Charcoal (not pure black) so it reads
  /// "dim daylight"; ink lightens, accents brighten to keep AA contrast on the dark card.
  static let midnight = JPTheme(
    id: "midnight", name: "Midnight Ledger", isDark: true, inMoreThemes: false,
    paper: "1B1A18", paper2: "232220", card: "232220", ink: "F2F1EC", inkSoft: "B8B6AE",
    inkFaint: "9E9C90", line: "403C36", lineStrong: "4A453D", track: "4E4A40",
    ginger: "F0954A", gingerDeep: "FBA85F", sage: "5CC489", sageSoft: "6FAE84",
    honey: "EBB454", creamDeep: "2B2A27", gold: "FDCD2D", cta: "F0954A", ctaDeep: "D9822F",
    coral: "EE7A66", sageDeep: "5CC489", ctaText: "221D15")

  /// Ember Ledger — premium dark counterpart with a warmer, deeper amber cast than Midnight (a
  /// "fireside" mood, not a new hue family: same ginger/honey/gold/coral vocabulary, pushed deeper +
  /// more saturated). The first premium theme pack.
  static let ember = JPTheme(
    id: "ember", name: "Ember Ledger", isDark: true, inMoreThemes: true,
    paper: "1A130E", paper2: "241A12", card: "241A12", ink: "F5EDE2", inkSoft: "C9B8A4",
    inkFaint: "AE9A82", line: "3E2E1F", lineStrong: "4A3826", track: "4F3B27",
    ginger: "FF6A1A", gingerDeep: "FF9B63", sage: "6BCB8F", sageSoft: "7DBE96",
    honey: "F0BE5A", creamDeep: "352617", gold: "FFCF3D", cta: "FF7A2F", ctaDeep: "F36B21",
    coral: "F17E5E", sageDeep: "6BCB8F", ctaText: "1A130E")

  /// Terminal-inspired premium theme packs. Palettes are grounded in yenchat's (YEN's sibling
  /// terminal-app) real shipped theme catalog — background/foreground/ANSI hex pulled directly from
  /// its theme files — then mapped onto JPTheme's role system (paper/card/ink/accent) and iterated
  /// until every WCAG-AA floor in `ThemeTests` passes. `ctaText` is white on all of these (their
  /// accent colors are mid-bright, not blindingly bright, so white reads on the CTA gradient).
  static let yen = JPTheme(
    id: "yen", name: "YEN", isDark: true, inMoreThemes: true,
    paper: "20252F", paper2: "2B313D", card: "2A303B", ink: "FFFFFF", inkSoft: "C9D1D9",
    inkFaint: "AEB7C2", line: "454D5A", lineStrong: "596372", track: "39414D",
    ginger: "56B6C2", gingerDeep: "6CC7D1", sage: "98C379", sageSoft: "ADCF94",
    honey: "E5C07B", creamDeep: "303744", gold: "E5C07B", cta: "347985", ctaDeep: "2B6771",
    coral: "E2757D", sageDeep: "B7E39D", ctaText: "FFFFFF")

  static let retroTerminal = JPTheme(
    id: "retroterminal", name: "Retro Terminal", isDark: true, inMoreThemes: true,
    paper: "030604", paper2: "09140C", card: "08110A", ink: "7CFF91", inkSoft: "5BBA6A",
    inkFaint: "4C9D5A", line: "18301D", lineStrong: "24492B", track: "112215",
    ginger: "4CA66B", gingerDeep: "4CA66B", sage: "33FF66", sageSoft: "42FF6F",
    honey: "9CE287", creamDeep: "0C180F", gold: "9CE287", cta: "3B8254", ctaDeep: "336F47",
    coral: "2FA34F", sageDeep: "33FF66", ctaText: "FFFFFF")

  static let dracula = JPTheme(
    id: "dracula", name: "Dracula", isDark: true, inMoreThemes: true,
    paper: "21222C", paper2: "2B2D39", card: "2D2F3D", ink: "F8F8F2", inkSoft: "C7C7C4",
    inkFaint: "A5A6A7", line: "494B54", lineStrong: "5E6067", track: "3D3F49",
    ginger: "FF79C6", gingerDeep: "FF79C6", sage: "50FA7B", sageSoft: "72FA93",
    honey: "F1FA8C", creamDeep: "343641", gold: "F1FA8C", cta: "9B3F79", ctaDeep: "843666",
    coral: "FF5A5A", sageDeep: "50FA7B", ctaText: "FFFFFF")

  static let nord = JPTheme(
    id: "nord", name: "Nord", isDark: true, inMoreThemes: true,
    paper: "252B36", paper2: "303744", card: "333B49", ink: "E5E9F0", inkSoft: "B5BDCA",
    inkFaint: "A9AEB7", line: "494F5B", lineStrong: "5A606C", track: "3F4551",
    ginger: "88C0D0", gingerDeep: "88C0D0", sage: "A3BE8C", sageSoft: "AEC49F",
    honey: "EBCB8B", creamDeep: "3B4352", gold: "EBCB8B", cta: "527987", ctaDeep: "466773",
    coral: "D08C92", sageDeep: "C6D8B5", ctaText: "FFFFFF")

  static let gruvboxDark = JPTheme(
    id: "gruvboxdark", name: "Gruvbox Dark", isDark: true, inMoreThemes: true,
    paper: "1D2021", paper2: "282828", card: "32302F", ink: "FBF1C7", inkSoft: "C8BFA3",
    inkFaint: "A9A08B", line: "47453E", lineStrong: "5B574C", track: "3C3A36",
    ginger: "FE8019", gingerDeep: "FE9D45", sage: "B8BB26", sageSoft: "C7C84A",
    honey: "FABD2F", creamDeep: "3C3836", gold: "FABD2F", cta: "A94D08", ctaDeep: "8E4006",
    coral: "DE736E", sageDeep: "D6D85A", ctaText: "FFFFFF")

  static let solarizedDark = JPTheme(
    id: "solarizeddark", name: "Solarized Dark", isDark: true, inMoreThemes: true,
    paper: "00232C", paper2: "07313B", card: "073642", ink: "EEE8D5", inkSoft: "AAB8B6",
    inkFaint: "93A6A9", line: "153C45", lineStrong: "22464F", track: "001F27",
    ginger: "4AA3E0", gingerDeep: "55ADE5", sage: "859900", sageSoft: "85981E",
    honey: "B58900", creamDeep: "08313C", gold: "B58900", cta: "2E75A7", ctaDeep: "26638E",
    coral: "E56967", sageDeep: "C8D66A", ctaText: "FFFFFF")

  static let monokaiPro = JPTheme(
    id: "monokaipro", name: "Monokai Pro", isDark: true, inMoreThemes: true,
    paper: "221F22", paper2: "2D2A2E", card: "363237", ink: "FCFCFA", inkSoft: "CBC9CA",
    inkFaint: "A9A8A8", line: "4E4C4F", lineStrong: "636163", track: "423F42",
    ginger: "FC9867", gingerDeep: "FC9867", sage: "A9DC76", sageSoft: "BAE290",
    honey: "FFD866", creamDeep: "39373A", gold: "FFD866", cta: "A46243", ctaDeep: "8B5439",
    coral: "FF6188", sageDeep: "A9DC76", ctaText: "FFFFFF")

  static let oneDark = JPTheme(
    id: "onedark", name: "One Dark", isDark: true, inMoreThemes: true,
    paper: "191C21", paper2: "21252B", card: "282C34", ink: "D7DAE0", inkSoft: "A7ADB8",
    inkFaint: "9499A0", line: "373C43", lineStrong: "454A51", track: "3A4049",
    ginger: "61AFEF", gingerDeep: "61AFEF", sage: "98C379", sageSoft: "9CC087",
    honey: "E5C07B", creamDeep: "292D34", gold: "E5C07B", cta: "4378A5", ctaDeep: "38678C",
    coral: "E06C75", sageDeep: "98C379", ctaText: "FFFFFF")

  static let tokyoNight = JPTheme(
    id: "tokyonight", name: "Tokyo Night", isDark: true, inMoreThemes: true,
    paper: "13141C", paper2: "1A1B26", card: "202336", ink: "C0CAF5", inkSoft: "9EA7D1",
    inkFaint: "8A8FAA", line: "353747", lineStrong: "45485C", track: "34384B",
    ginger: "7AA2F7", gingerDeep: "7AA2F7", sage: "9ECE6A", sageSoft: "A5CD86",
    honey: "E0AF68", creamDeep: "242632", gold: "E0AF68", cta: "556FAA", ctaDeep: "476091",
    coral: "F7768E", sageDeep: "9ECE6A", ctaText: "FFFFFF")

  static let catppuccinMocha = JPTheme(
    id: "catppuccinmocha", name: "Catppuccin Mocha", isDark: true, inMoreThemes: true,
    paper: "15151F", paper2: "1E1E2E", card: "29293D", ink: "CDD6F4", inkSoft: "A6ADC8",
    inkFaint: "8E93AA", line: "3A3B4E", lineStrong: "4C4E61", track: "414158",
    ginger: "CBA6F7", gingerDeep: "CBA6F7", sage: "A6E3A1", sageSoft: "AEE0B2",
    honey: "F9E2AF", creamDeep: "313244", gold: "F9E2AF", cta: "765B98", ctaDeep: "644D81",
    coral: "F38BA8", sageDeep: "A6E3A1", ctaText: "FFFFFF")

  static let rosePine = JPTheme(
    id: "rosepine", name: "Rosé Pine", isDark: true, inMoreThemes: true,
    paper: "12101A", paper2: "191724", card: "252132", ink: "E0DEF4", inkSoft: "B2AEC7",
    inkFaint: "908EA1", line: "393745", lineStrong: "4D4B5A", track: "3B354B",
    ginger: "EB6F92", gingerDeep: "F08AAA", sage: "9CCFD8", sageSoft: "AFD9E0",
    honey: "F6C177", creamDeep: "2A2738", gold: "F6C177", cta: "8B3D58", ctaDeep: "76344B",
    coral: "C4A7E7", sageDeep: "B8E5ED", ctaText: "FFFFFF")

  static let everforestDark = JPTheme(
    id: "everforestdark", name: "Everforest Dark", isDark: true, inMoreThemes: true,
    paper: "171C1E", paper2: "1E2326", card: "2D353B", ink: "D3C6AA", inkSoft: "B4AA93",
    inkFaint: "AAA38F", line: "3B3D3B", lineStrong: "4D4D48", track: "424C50",
    ginger: "A7C080", gingerDeep: "B3CA91", sage: "83C092", sageSoft: "9BCBA7",
    honey: "DBBC7F", creamDeep: "343F44", gold: "DBBC7F", cta: "65794D", ctaDeep: "566741",
    coral: "E67E80", sageDeep: "C0D5A0", ctaText: "FFFFFF")

  static let githubDark = JPTheme(
    id: "githubdark", name: "GitHub Dark", isDark: true, inMoreThemes: true,
    paper: "080A0D", paper2: "0D1117", card: "161B22", ink: "F0F6FC", inkSoft: "B1BAC4",
    inkFaint: "9AA4AF", line: "30363D", lineStrong: "484F58", track: "252B33",
    ginger: "6CA4F8", gingerDeep: "6CA4F8", sage: "56D364", sageSoft: "61C670",
    honey: "E3B341", creamDeep: "171A1E", gold: "E3B341", cta: "4B71AB", ctaDeep: "3F6091",
    coral: "F78166", sageDeep: "56D364", ctaText: "FFFFFF")

  // Four more terminal packs rounding out the catalog — same yenchat-catalog sourcing and WCAG-AA
  // tuning as the packs above (Ayu Mirage, Night Owl, Catppuccin Macchiato, Palenight).
  static let ayuMirage = JPTheme(
    id: "ayumirage", name: "Ayu Mirage", isDark: true, inMoreThemes: true,
    paper: "171B24", paper2: "1F2430", card: "2A3040", ink: "FFF3E0", inkSoft: "C7C0B3",
    inkFaint: "9A988F", line: "3D4350", lineStrong: "4C5361", track: "41495B",
    ginger: "FFCC66", gingerDeep: "FFD47F", sage: "87D96C", sageSoft: "A6CC70",
    honey: "FFAD66", creamDeep: "343A48", gold: "FFD173", cta: "8A641F", ctaDeep: "75541A",
    coral: "F28779", sageDeep: "9FE080", ctaText: "FFFFFF")

  static let nightOwl = JPTheme(
    id: "nightowl", name: "Night Owl", isDark: true, inMoreThemes: true,
    paper: "00111F", paper2: "011627", card: "0B2942", ink: "D6DEEB", inkSoft: "A9B7CB",
    inkFaint: "8794A8", line: "1E3A52", lineStrong: "2A4763", track: "19415F",
    ginger: "82AAFF", gingerDeep: "82AAFF", sage: "4BD88A", sageSoft: "ADDB67",
    honey: "ECC48D", creamDeep: "0B2136", gold: "ECC48D", cta: "3A6FB0", ctaDeep: "315E96",
    coral: "FF5874", sageDeep: "4BD88A", ctaText: "FFFFFF")

  static let catppuccinMacchiato = JPTheme(
    id: "catppuccinmacchiato", name: "Catppuccin Macchiato", isDark: true, inMoreThemes: true,
    paper: "1B1D2B", paper2: "24273A", card: "30344C", ink: "CAD3F5", inkSoft: "AEB7D0",
    inkFaint: "989FBC", line: "434763", lineStrong: "545977", track: "1F2233",
    ginger: "8AADF4", gingerDeep: "8AADF4", sage: "A6DA95", sageSoft: "B4E0A6",
    honey: "EED49F", creamDeep: "2C2F47", gold: "EED49F", cta: "4F6DA8", ctaDeep: "435C8E",
    coral: "ED8796", sageDeep: "A6DA95", ctaText: "FFFFFF")

  static let palenight = JPTheme(
    id: "palenight", name: "Palenight", isDark: true, inMoreThemes: true,
    paper: "202331", paper2: "292D3E", card: "353A50", ink: "E6E9FF", inkSoft: "B8BEDD",
    inkFaint: "AEB5D6", line: "474C63", lineStrong: "565C77", track: "252838",
    ginger: "C792EA", gingerDeep: "D2A7EF", sage: "C3E88D", sageSoft: "D0EDA0",
    honey: "FFCB6B", creamDeep: "3C4058", gold: "FFCB6B", cta: "76528D", ctaDeep: "644678",
    coral: "F07178", sageDeep: "C3E88D", ctaText: "FFFFFF")

  // Four more terminal packs (Kanagawa Wave, Oceanic Next, Cobalt2, Synthwave) — same yenchat-catalog
  // sourcing and WCAG-AA tuning as the packs above. Kanagawa keeps its ink/indigo "wave" cast, Oceanic
  // its teal-slate, Cobalt2 its deep-blue-with-electric-blue accent, Synthwave its purple canvas keyed
  // to its cyan (not pink) accent so it stays a distinct picker signature from Dracula.
  static let kanagawaWave = JPTheme(
    id: "kanagawawave", name: "Kanagawa Wave", isDark: true, inMoreThemes: true,
    paper: "16161D", paper2: "1F1F28", card: "2A2A37", ink: "DCD7BA", inkSoft: "C8C093",
    inkFaint: "A6A08A", line: "363646", lineStrong: "45455A", track: "363646",
    ginger: "7E9CD8", gingerDeep: "94AEE0", sage: "98BB6C", sageSoft: "ABC784",
    honey: "E6C384", creamDeep: "30303F", gold: "E6C384", cta: "4A5D8A", ctaDeep: "3E4F76",
    coral: "E46876", sageDeep: "B4D28A", ctaText: "FFFFFF")

  static let oceanicNext = JPTheme(
    id: "oceanicnext", name: "Oceanic Next", isDark: true, inMoreThemes: true,
    paper: "16232B", paper2: "1B2B34", card: "22313A", ink: "CDD3DE", inkSoft: "B0B7C2",
    inkFaint: "9BA3AE", line: "31424B", lineStrong: "40525C", track: "31424B",
    ginger: "6699CC", gingerDeep: "7DA9D6", sage: "99C794", sageSoft: "ABD1A6",
    honey: "FAC863", creamDeep: "2A3A44", gold: "FAC863", cta: "3E6EA0", ctaDeep: "355E88",
    coral: "EC5F67", sageDeep: "B0D8AC", ctaText: "FFFFFF")

  static let cobalt2 = JPTheme(
    id: "cobalt2", name: "Cobalt2", isDark: true, inMoreThemes: true,
    paper: "12293A", paper2: "163243", card: "1B3D57", ink: "F4F8FB", inkSoft: "C4D2DD",
    inkFaint: "A6B7C6", line: "2A4E6B", lineStrong: "38607F", track: "2A4E6B",
    ginger: "2FA8FF", gingerDeep: "5CBBFF", sage: "4CD964", sageSoft: "6FE083",
    honey: "FFC600", creamDeep: "234863", gold: "FFC600", cta: "1E6FB0", ctaDeep: "195E96",
    coral: "FF628C", sageDeep: "7DE68F", ctaText: "FFFFFF")

  static let synthwave = JPTheme(
    id: "synthwave", name: "Synthwave", isDark: true, inMoreThemes: true,
    paper: "201B2D", paper2: "262335", card: "2A2139", ink: "F8F8F2", inkSoft: "CFC7DB",
    inkFaint: "ADA3BF", line: "3D3352", lineStrong: "4E4167", track: "3D3352",
    ginger: "36F9F6", gingerDeep: "63FAF8", sage: "72F1B8", sageSoft: "8FF3C7",
    honey: "FEDE5D", creamDeep: "332A45", gold: "FEDE5D", cta: "2C7C82", ctaDeep: "25696E",
    coral: "FE4450", sageDeep: "90F3C6", ctaText: "FFFFFF")

  /// The registry. To add a theme, append a `JPTheme(... inMoreThemes: true)` here — no
  /// other code changes are needed.
  static let all: [JPTheme] = [
    sunlit, midnight, ember, yen, retroTerminal, dracula, nord, gruvboxDark, solarizedDark,
    monokaiPro, oneDark, tokyoNight, catppuccinMocha, rosePine, everforestDark, githubDark,
    ayuMirage, nightOwl, catppuccinMacchiato, palenight,
    kanagawaWave, oceanicNext, cobalt2, synthwave,
  ]

  static func with(id: String) -> JPTheme? { all.first { $0.id == id } }

  /// UserDefaults key for the persisted theme id.
  static let storageKey = "JPtheCat.themeID"

  /// The active theme — the single source every `JPAppColor` token resolves from, so color reads stay
  /// synchronous and isolation-free. Mutated only on the main thread by `ThemeManager` and read only
  /// on the main thread (SwiftUI bodies / AppKit drawing), so it is race-free in practice;
  /// `nonisolated(unsafe)` records that contract. SwiftUI re-renders because it observes
  /// `ThemeManager.theme`, which mirrors this value.
  nonisolated(unsafe) static var current: JPTheme = {
    let storedID = UserDefaults.standard.string(forKey: storageKey)
    return storedID.flatMap(JPTheme.with(id:)) ?? .sunlit
  }()
}

/// Active-theme owner: persists the selection, applies the matching AppKit appearance, and publishes
/// changes so SwiftUI re-renders and the AppKit menu-bar pill redraws. A singleton whose `@Published`
/// `theme` mirrors `JPTheme.current` (the token source) so views and colors share one truth.
@MainActor
final class ThemeManager: ObservableObject {
  static let shared = ThemeManager()
  /// Posted after the active theme changes so non-SwiftUI surfaces (the status-item pill) can redraw.
  static let didChangeNotification = Notification.Name("JPtheCat.themeDidChange")

  @Published private(set) var theme: JPTheme

  /// Where the selected theme id persists. Production (`shared`) uses `.standard`; the test seam below
  /// injects an isolated suite so parallel xctest workers never race on the on-disk `JPTheme.storageKey`.
  private let defaults: UserDefaults

  private init() {
    defaults = .standard
    theme = JPTheme.current
  }

  /// Test-only seam: an isolated manager that persists to `defaults` (not `.standard`) starting from
  /// `theme`. Runtime code uses only `shared`; this exists so `ThemeTests` can assert persistence
  /// without touching the shared on-disk defaults that parallel xctest workers all read/write.
  init(defaults: UserDefaults, theme: JPTheme = .sunlit) {
    self.defaults = defaults
    self.theme = theme
  }

  /// Every shipped theme is selectable — JP is free.
  var selectable: [JPTheme] { JPTheme.all }

  /// Apply the active theme's appearance to the app (call once at launch, and after a change).
  /// `NSApplication.shared` (not the `NSApp` IUO) so this is safe from unit tests too.
  ///
  /// [Regression guard] Only touch `NSApp.appearance` when the light/dark family actually changes —
  /// reassigning the SAME appearance still forces an expensive AppKit-wide re-resolve of
  /// `effectiveAppearance`, and most theme switches share a family.
  func apply() {
    let target: NSAppearance.Name = theme.isDark ? .darkAqua : .aqua
    guard NSApplication.shared.appearance?.name != target else { return }
    NSApplication.shared.appearance = NSAppearance(named: target)
  }

  func select(_ next: JPTheme) {
    guard next.id != theme.id else { return }
    JPTheme.current = next  // update the token source first, then the observable mirror
    theme = next
    defaults.set(next.id, forKey: JPTheme.storageKey)
    apply()
    NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
  }

  func selectWithClick(_ next: JPTheme) {
    InteractiveSounds.shared.topClick()
    select(next)
  }
}
