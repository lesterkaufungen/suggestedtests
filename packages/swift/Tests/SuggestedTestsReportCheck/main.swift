// Started by SystemProbeTests in a fresh process, since the bridge's startup
// report goes to the process's stderr. The mode is the first argument.
import Foundation
import SuggestedTests

func verbose() -> Bool { (try? SystemProbe.verbose()) ?? false }

switch CommandLine.arguments.dropFirst().first ?? "" {
case "nothing":
  // Uses an API that never calls the bridge: using any API loads it.
  _ = TestData(seed: 1)
case "load":
  print(SystemProbe.isAvailable, verbose())
case "set":
  let first = (try? SystemProbe.setVerbose(true)) ?? false
  let second = (try? SystemProbe.setVerbose(true)) ?? false
  let third = (try? SystemProbe.setVerbose(false)) ?? false
  print(first, second, third, verbose())
default:
  FileHandle.standardError.write(
    "usage: SuggestedTestsReportCheck nothing|load|set\n".data(using: .utf8)!)
  exit(64)
}
