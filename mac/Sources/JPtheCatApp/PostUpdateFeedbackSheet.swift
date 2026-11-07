import AppKit
import JPtheCatCore
import SwiftUI

/// The one time JP asks for something back: a single text box, shown on the first dashboard open
/// after the app's version changes.
///
/// No stars, no 1-5 gate, no thumbs — a rating is a step in front of the only thing worth having,
/// which is words. Send routes through the same `SupportReportClient` → `/api/support-report` path as the
/// Settings support report, carrying `PostUpdateFeedbackReport`'s two-fact body (build + macOS) and
/// nothing else. Dismissing sends nothing at all.
///
/// The presentation decision lives in `PostUpdateFeedbackGate` (pure, tested); this view only renders
/// and sends. `PostUpdateFeedbackSheetBody` is the pure half so the brand-fidelity harness can render
/// every state without a network stack.
struct PostUpdateFeedbackSheet: View {
  let version: String
  let report: String
  /// Called with `optOut: true` when the user picks "Don't ask again".
  let onClose: (_ optOut: Bool) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var message = ""
  @State private var contactEmail = ""
  @State private var sending = false
  @State private var status: PostUpdateFeedbackStatus?

  var body: some View {
    PostUpdateFeedbackSheetBody(
      version: version,
      message: $message,
      contactEmail: $contactEmail,
      sending: sending,
      status: status,
      onSend: send,
      onNotNow: { close(optOut: false) },
      onNeverAsk: { close(optOut: true) })
  }

  private func close(optOut: Bool) {
    dismiss()
    onClose(optOut)
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
        status = .sent
        close(optOut: false)
      case .invalidEmail:
        status = .invalidEmail
      case .failed:
        status = .failed
      }
    }
  }
}

enum PostUpdateFeedbackStatus: Equatable {
  case sent
  case invalidEmail
  case failed

  var text: String {
    switch self {
    case .sent: "Sent — thank you."
    case .invalidEmail: "That email doesn’t look right. Leave it blank or enter a valid address."
    case .failed: "Couldn’t send. Try again, or email support@JPtheCat.com directly."
    }
  }

  var isError: Bool { self != .sent }
}

/// Pure presentation — no singletons, no network, every input injected.
struct PostUpdateFeedbackSheetBody: View {
  let version: String
  @Binding var message: String
  @Binding var contactEmail: String
  var sending = false
  var status: PostUpdateFeedbackStatus?
  var onSend: () -> Void = {}
  var onNotNow: () -> Void = {}
  var onNeverAsk: () -> Void = {}
  // A static leaf that reads `JP.*` freezes at its first-render theme when the parent's structural
  // diff skips it, so take the theme dependency explicitly (see mac/AGENTS.md).
  // periphery:ignore - intentional theme dependency.
  @ObservedObject private var themeManager = ThemeManager.shared

  private var canSend: Bool {
    !sending && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      messageField
      emailField
      disclosure
      if let status {
        Text(status.text)
          .font(JPAppFont.micro)
          .foregroundStyle(status.isError ? JP.gingerDeep : JP.sage)
          .fixedSize(horizontal: false, vertical: true)
      }
      buttons
    }
    .padding(18)
    .frame(width: 460)
    .background(JP.card)
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      if let mark = AppResources.image(forResource: "jp-menubar") {
        Image(nsImage: mark)
          .resizable()
          .frame(width: 40, height: 40)
          .clipShape(RoundedRectangle(cornerRadius: JPAppRadius.card, style: .continuous))
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 3) {
        Text("Just updated to \(version)")
          .font(JPAppFont.bodyStrong)
          .foregroundStyle(JP.ink)
        Text("How is JP the Cat working for you? Anything at all — a bug, a papercut, a provider you wish it read.")
          .font(JPAppFont.body)
          .foregroundStyle(JP.inkSoft)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var messageField: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Your thoughts").font(JPAppFont.eyebrowStrong).foregroundStyle(JP.inkFaint)
      JPTextEditorField(
        placeholder: "Tell JP anything.",
        text: $message,
        disabled: sending,
        accessibilityLabel: "Your feedback on JP the Cat")
    }
  }

  private var emailField: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Your email (optional)").font(JPAppFont.eyebrowStrong).foregroundStyle(JP.inkFaint)
      TextField("you@example.com", text: $contactEmail)
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .font(JPAppFont.body)
        .accessibilityLabel("Your email (optional)")
        .disabled(sending)
      Text("Only add this if you want a reply. JP does not store it in the app.")
        .font(JPAppFont.micro)
        .foregroundStyle(JP.inkSoft)
    }
  }

  private var disclosure: some View {
    Text(
      "JP emails this to support@JPtheCat.com with your app version and macOS version attached. "
        + "No usage data, no costs, no provider list, nothing from your projects."
    )
    .font(JPAppFont.micro)
    .foregroundStyle(JP.inkSoft)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var buttons: some View {
    HStack(spacing: 10) {
      Button("Not now") { onNotNow() }
        .disabled(sending)
      // Deliberately low-emphasis and NOT `.buttonStyle(.link)`: link style paints system blue, which
      // is not in this palette, and permanently opting out should not out-shout "Not now".
      Button { onNeverAsk() } label: {
        Text("Don’t ask again")
          .font(JPAppFont.micro)
          .foregroundStyle(JP.inkSoft)
          .underline()
      }
      .buttonStyle(.plain)
      .disabled(sending)
      Spacer()
      Button(sending ? "Sending…" : "Send") { onSend() }
        .buttonStyle(.borderedProminent)
        // Brand CTA is ginger-deep; the default prominent tint is system blue (see root AGENTS.md).
        .tint(JP.gingerDeep)
        .disabled(!canSend)
    }
  }
}
