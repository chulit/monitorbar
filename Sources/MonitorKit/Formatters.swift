import Foundation

/// Display formatting, pinned to the reference layout: one decimal on
/// percentages ("86.5%"), two decimals on GB sizes ("6,44 GB" in an
/// Indonesian locale), network rates in bits ("199 kb/s", "1 Mb/s").
/// Every function takes a locale so tests can pin exact output.
public enum Format {
  private static func number(
    _ value: Double, minFraction: Int, maxFraction: Int, locale: Locale
  ) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = minFraction
    formatter.maximumFractionDigits = maxFraction
    formatter.locale = locale
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
  }

  /// Fraction 0...1 → "86.5%".
  public static func percent(fraction: Double, locale: Locale = .current) -> String {
    number(fraction * 100, minFraction: 1, maxFraction: 1, locale: locale) + "%"
  }

  /// Fraction 0...1 → "75%" (no decimals, for compact badges).
  public static func percentWhole(fraction: Double, locale: Locale = .current) -> String {
    number(fraction * 100, minFraction: 0, maxFraction: 0, locale: locale) + "%"
  }

  /// A percent value that is already in percent units → "22.6%".
  public static func percent(value: Double, locale: Locale = .current) -> String {
    number(value, minFraction: 1, maxFraction: 1, locale: locale) + "%"
  }

  /// 1024-based sizes: "6,44 GB", "227 MB", "512 KB", "900 B".
  public static func bytes(_ bytes: UInt64, locale: Locale = .current) -> String {
    let gib = 1_073_741_824.0
    let mib = 1_048_576.0
    let kib = 1_024.0
    let value = Double(bytes)
    if value >= gib {
      return number(value / gib, minFraction: 2, maxFraction: 2, locale: locale) + " GB"
    }
    if value >= mib {
      return number(value / mib, minFraction: 0, maxFraction: 0, locale: locale) + " MB"
    }
    if value >= kib {
      return number(value / kib, minFraction: 0, maxFraction: 0, locale: locale) + " KB"
    }
    return "\(bytes) B"
  }

  /// Network throughput in bits per second: "199 kb/s", "1 Mb/s".
  public static func rate(bytesPerSec: Double, locale: Locale = .current) -> String {
    let bits = max(bytesPerSec, 0) * 8
    if bits >= 1_000_000 {
      return number(bits / 1_000_000, minFraction: 0, maxFraction: 1, locale: locale) + " Mb/s"
    }
    if bits >= 1_000 {
      return number(bits / 1_000, minFraction: 0, maxFraction: 0, locale: locale) + " kb/s"
    }
    return number(bits, minFraction: 0, maxFraction: 0, locale: locale) + " b/s"
  }

  /// "21d 10h 54m", "10h 54m", "54m", "0m".
  public static func uptime(_ interval: TimeInterval) -> String {
    let totalMinutes = Int(interval) / 60
    let days = totalMinutes / 1_440
    let hours = (totalMinutes % 1_440) / 60
    let minutes = totalMinutes % 60
    if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
  }

  /// Degrees for the temperature card: "60°C".
  public static func temperature(celsius: Double) -> String {
    "\(Int(celsius.rounded()))°C"
  }
}

/// Loose IPv4 check for the public-IP lookup result before it is shown.
public func isValidIPv4(_ string: String) -> Bool {
  let parts = string.split(separator: ".")
  guard parts.count == 4 else { return false }
  return parts.allSatisfy { part in
    guard let value = Int(part), (0...255).contains(value), !part.isEmpty else {
      return false
    }
    return String(value) == String(part) || part == "0"
  }
}
