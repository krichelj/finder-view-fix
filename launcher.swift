// FinderViewFix launcher: the launchd job's executable. macOS privacy (TCC)
// attributes file access to the job's executable, and a shell run directly by
// launchd cannot list ~/Documents, ~/Desktop, ~/Downloads or iCloud Drive.
// This tiny signed app is what you grant Full Disk Access to, once; it just
// runs maintain.sh from the installed copy with a sane PATH.
import Foundation
let sup = NSHomeDirectory() + "/Library/Application Support/finder-view-fix"
let p = Process()
p.executableURL = URL(fileURLWithPath: "/bin/bash")
p.arguments = [sup + "/maintain.sh"] + CommandLine.arguments.dropFirst()
var env = ProcessInfo.processInfo.environment
env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + NSHomeDirectory() + "/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
p.environment = env
do { try p.run() } catch { FileHandle.standardError.write("cannot run maintain.sh: \(error)\n".data(using: .utf8)!); exit(1) }
p.waitUntilExit()
exit(p.terminationStatus)
