// Prints the CGWindowID of the frontmost on-screen Finder browser window
// whose title equals argv[1] (used with `screencapture -l` so tests capture
// that window even when another app covers it).
import CoreGraphics
import Foundation
let want = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in info where (w[kCGWindowOwnerName as String] as? String) == "Finder" && (w[kCGWindowLayer as String] as? Int) == 0 {
  if want.isEmpty || (w[kCGWindowName as String] as? String) == want { print(w[kCGWindowNumber as String] as! Int); exit(0) }
}
exit(1)
