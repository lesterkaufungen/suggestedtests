/// `"412µs"`, `"1.25ms"`, `"2.01s"`: the same format as the other packages.
func formatNanoseconds(_ ns: Double) -> String {
  let us = ns / 1000
  if abs(us) < 1000 { return "\(Int(us.rounded()))µs" }
  if abs(us) < 1_000_000 { return fixed(us / 1000, 2) + "ms" }
  return fixed(us / 1_000_000, 2) + "s"
}

/// `"512 B"`, `"40.1 MiB"`.
public func formatBytes(_ bytes: Int) -> String {
  let units = ["B", "KiB", "MiB", "GiB", "TiB"]
  var value = Double(bytes.magnitude)
  var unit = 0
  while value >= 1024, unit < units.count - 1 {
    value /= 1024
    unit += 1
  }
  if unit == 0 { return "\(bytes) B" }
  return (bytes < 0 ? "-" : "") + fixed(value, 1) + " " + units[unit]
}

/// `value` with `digits` decimals, without Foundation's locale-dependent formatting.
func fixed(_ value: Double, _ digits: Int) -> String {
  var scale = 1.0
  for _ in 0..<digits { scale *= 10 }
  let scaled = (value.magnitude * scale).rounded()
  var whole = String(Int(scaled / scale))
  if value < 0, scaled != 0 { whole = "-" + whole }
  guard digits > 0 else { return whole }
  var fraction = String(Int(scaled.truncatingRemainder(dividingBy: scale)))
  while fraction.count < digits { fraction = "0" + fraction }
  return whole + "." + fraction
}
