import Darwin
import Foundation
import IOKit

/// CPU temperature from the AppleSMC user client. Verified sensor keys
/// on the user's MacBook Air M2: Tp01 is the CPU sensor, Tp05 a second
/// CPU-zone sensor used as fallback. If no key reads, the card honestly
/// shows "—" — there is no public Thermal API that returns degrees.
public final class TemperatureReader {
  private static let sensorKeys = ["Tp01", "Tp05"]
  private var connection: io_connect_t = 0

  public init() {}

  deinit {
    if connection != 0 {
      IOServiceClose(connection)
    }
  }

  public func readCelsius() -> Double? {
    for key in Self.sensorKeys {
      if let value = read(key), value > 0, value < 130 {
        return value
      }
    }
    return nil
  }

  private func read(_ key: String) -> Double? {
    let code = Self.keyCode(key)
    guard open(),
      let (dataSize, type) = keyInfo(code),
      dataSize > 0, dataSize <= 32,
      let bytes = readBytes(code, size: dataSize, type: type)
    else { return nil }
    switch type {
    case "flt ":
      return bytes.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return nil }
        var value: Float = 0
        memcpy(&value, base, min(buffer.count, 4))
        return Double(value)
      }
    case "sp78":
      guard bytes.count >= 2 else { return nil }
      let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
      return Double(raw) / 256.0
    default:
      return nil
    }
  }

  private func open() -> Bool {
    if connection != 0 { return true }
    guard let matching = IOServiceMatching("AppleSMC") as CFDictionary? else {
      return false
    }
    let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    guard service != 0 else { return false }
    defer { IOObjectRelease(service) }
    var newConnection: io_connect_t = 0
    guard IOServiceOpen(service, mach_task_self_, 0, &newConnection) == KERN_SUCCESS else {
      return false
    }
    connection = newConnection
    return true
  }

  private func keyInfo(_ code: UInt32) -> (size: UInt32, type: String)? {
    var input = SMCParam()
    input.key = code
    input.data8 = 9
    guard let output = smcCall(&input), output.result == 0 else { return nil }
    return (output.keyInfo.dataSize, Self.osType(output.keyInfo.dataType))
  }

  private func readBytes(_ code: UInt32, size: UInt32, type: String) -> [UInt8]? {
    var input = SMCParam()
    input.key = code
    input.data8 = 5
    input.data32 = size
    input.keyInfo.dataSize = size
    input.keyInfo.dataType = Self.keyCode(type)
    guard let output = smcCall(&input), output.result == 0 else { return nil }
    return withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(size))) }
  }

  private func smcCall(_ input: inout SMCParam) -> SMCParam? {
    var output = SMCParam()
    var outputSize = MemoryLayout<SMCParam>.size
    let status = withUnsafePointer(to: &input) { inPtr in
      withUnsafeMutablePointer(to: &output) { outPtr in
        IOConnectCallStructMethod(
          connection, 2,
          UnsafeRawPointer(inPtr), MemoryLayout<SMCParam>.size,
          UnsafeMutableRawPointer(outPtr), &outputSize
        )
      }
    }
    guard status == KERN_SUCCESS else { return nil }
    return output
  }

  private static func keyCode(_ name: String) -> UInt32 {
    var result: UInt32 = 0
    for byte in name.utf8.prefix(4) {
      result = (result << 8) | UInt32(byte)
    }
    return result
  }

  private static func osType(_ code: UInt32) -> String {
    let bytes: [CChar] = [
      CChar(bitPattern: UInt8(truncatingIfNeeded: code >> 24)),
      CChar(bitPattern: UInt8(truncatingIfNeeded: code >> 16)),
      CChar(bitPattern: UInt8(truncatingIfNeeded: code >> 8)),
      CChar(bitPattern: UInt8(truncatingIfNeeded: code)),
      0,
    ]
    return bytes.withUnsafeBufferPointer { buffer in
      String(cString: buffer.baseAddress!)
    }
  }
}

private struct SMCVers {
  var major: CChar = 0
  var minor: CChar = 0
  var build: CChar = 0
  var reserved: CChar = 0
  var release: UInt16 = 0
}

private struct SMCPLimit {
  var version: UInt16 = 0
  var length: UInt16 = 0
  var cpu: UInt32 = 0
  var gpu: UInt32 = 0
  var mem: UInt32 = 0
}

private struct SMCKeyInfo {
  var dataSize: UInt32 = 0
  var dataType: UInt32 = 0
  var dataAttributes: UInt8 = 0
  var pad0: UInt8 = 0
  var pad1: UInt8 = 0
  var pad2: UInt8 = 0
}

private struct SMCParam {
  var key: UInt32 = 0
  var vers = SMCVers()
  var pLimit = SMCPLimit()
  var keyInfo = SMCKeyInfo()
  var result: UInt8 = 0
  var status: UInt8 = 0
  var data8: UInt8 = 0
  var data32: UInt32 = 0
  var bytes: (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
  ) = (
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  )

  init() {
    assert(MemoryLayout<SMCParam>.size == 80, "SMC user-client structure must be 80 bytes")
  }
}
