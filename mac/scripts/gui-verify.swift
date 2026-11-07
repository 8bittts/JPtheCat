// gui-verify.swift — headless GUI verification driver for the JP the Cat macOS app.
//
// Purpose: let an agent (or a human) SELF-VERIFY the running app's real UI without a person in the
// loop. In this repo's dev/CI environment the reliable automation stack is:
//   1. `screencapture` (full / -R region / -l window-id) — pixel-perfect window capture.
//   2. CGWindowList — locate JP windows + their on-screen bounds.
//   3. Accessibility (AXUIElement) — READ every labelled control and its frame, and PRESS/toggle any
//      of them via kAXPressAction (no screen coordinates, no window z-order fights).
//
// Raw synthetic CGEvent mouse clicks are NOT reliable here (they don't route to a non-frontmost
// window), so this tool drives the app through Accessibility instead — which needs no coordinates and
// works regardless of which window is frontmost. Screenshot capture is used only for VISUAL proof.
//
// Requires the controlling terminal to hold Accessibility + Screen Recording permission (already
// granted on the dev machine). Compiled + cached by `mac/scripts/gui-verify.sh`.
//
// Subcommands:
//   windows                 list JP the Cat on-screen windows (win id, bounds)
//   tree                    dump every labelled AX control (role + description) across all windows
//   frame <description>     print screen frame + center of the control(s) with that exact AX description
//   press <description>     AXPress the control with that exact AX description (opens tray, toggles a
//                           checkbox, clicks a footer icon, …) and print the result code
//   shot <winid> <path>     screencapture a single window by id to <path>
//
// Exit codes: 0 ok · 1 app not running · 2 bad args · 3 control not found · 4 AX not permitted.

import AppKit
import ApplicationServices

let bundleID = "com.8bittts.jpthecat"

func app() -> NSRunningApplication? {
  NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
}

/// All JP windows on screen, via CGWindowList (works regardless of z-order / key state).
func jpWindows() -> [(id: Int, name: String, bounds: CGRect)] {
  let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
  guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
  var out: [(Int, String, CGRect)] = []
  for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    guard owner.localizedCaseInsensitiveContains("JP the Cat") || owner.localizedCaseInsensitiveContains("JPtheCat")
    else { continue }
    let id = w[kCGWindowNumber as String] as? Int ?? -1
    let name = w[kCGWindowName as String] as? String ?? ""
    let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
    out.append((id, name, rect))
  }
  return out
}

/// Walk the AX tree of every app window, invoking `visit` on each element with its description.
func forEachControl(_ visit: (AXUIElement, String, String) -> Void) {
  guard let running = app() else { return }
  let ax = AXUIElementCreateApplication(running.processIdentifier)
  var winsRef: CFTypeRef?
  AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &winsRef)
  guard let wins = winsRef as? [AXUIElement] else { return }
  func walk(_ el: AXUIElement) {
    var rRef: CFTypeRef?; AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &rRef)
    var dRef: CFTypeRef?; AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &dRef)
    visit(el, (rRef as? String ?? ""), (dRef as? String ?? ""))
    var kRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kRef) == .success,
       let kids = kRef as? [AXUIElement] { for k in kids { walk(k) } }
  }
  for w in wins { walk(w) }
}

func frame(of el: AXUIElement) -> CGRect {
  var pRef: CFTypeRef?; var sRef: CFTypeRef?
  AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pRef)
  AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sRef)
  var pos = CGPoint.zero; var size = CGSize.zero
  if let p = pRef { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
  if let s = sRef { AXValueGetValue(s as! AXValue, .cgSize, &size) }
  return CGRect(origin: pos, size: size)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
  FileHandle.standardError.write(Data("usage: gui-verify <windows|tree|frame|press|shot> [...]\n".utf8))
  exit(2)
}

switch args[1] {
case "windows":
  let wins = jpWindows()
  if wins.isEmpty { print("(no JP the Cat windows on screen)") }
  for w in wins {
    print("win=\(w.id) name=\"\(w.name)\" bounds=(\(w.bounds.minX),\(w.bounds.minY),\(w.bounds.width)x\(w.bounds.height))")
  }

case "tree":
  guard app() != nil else { print("app not running"); exit(1) }
  if !AXIsProcessTrusted() { print("AX not trusted — grant Accessibility to the terminal"); exit(4) }
  var any = false
  forEachControl { _, role, desc in
    if role.contains("Button") || role.contains("CheckBox") || !desc.isEmpty {
      any = true
      print("\(role) desc=\"\(desc)\"")
    }
  }
  if !any { print("(empty AX tree)") }

case "frame":
  guard args.count >= 3 else { print("usage: gui-verify frame <description>"); exit(2) }
  let target = args[2]
  var hit = false
  forEachControl { el, _, desc in
    guard desc == target else { return }
    hit = true
    let f = frame(of: el)
    print("\"\(target)\" pos=(\(f.minX),\(f.minY)) size=(\(f.width)x\(f.height)) center=(\(f.midX),\(f.midY))")
  }
  if !hit { print("NOT FOUND: \(target)"); exit(3) }

case "press":
  guard args.count >= 3 else { print("usage: gui-verify press <description>"); exit(2) }
  guard let running = app() else { print("app not running"); exit(1) }
  if !AXIsProcessTrusted() { print("AX not trusted — grant Accessibility to the terminal"); exit(4) }
  running.activate()
  usleep(200_000)
  var target: AXUIElement?
  forEachControl { el, _, desc in if target == nil, desc == args[2] { target = el } }
  guard let btn = target else { print("NOT FOUND: \(args[2])"); exit(3) }
  let r = AXUIElementPerformAction(btn, kAXPressAction as CFString)
  print("pressed \"\(args[2])\" result=\(r.rawValue)")
  exit(r == .success ? 0 : 3)

case "shot":
  guard args.count >= 4, let winid = Int(args[2]) else { print("usage: gui-verify shot <winid> <path>"); exit(2) }
  let task = Process()
  task.launchPath = "/usr/sbin/screencapture"
  task.arguments = ["-o", "-x", "-l\(winid)", args[3]]
  try? task.run(); task.waitUntilExit()
  print("wrote \(args[3]) (exit \(task.terminationStatus))")
  exit(task.terminationStatus == 0 ? 0 : 1)

default:
  FileHandle.standardError.write(Data("unknown subcommand: \(args[1])\n".utf8))
  exit(2)
}
