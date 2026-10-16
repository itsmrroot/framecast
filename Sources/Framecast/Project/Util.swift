import Foundation
import CoreGraphics
import CoreMedia

@inline(__always) func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }
@inline(__always) func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

func smootherstep(_ x: Double) -> Double {
    let t = clamp(x, 0, 1)
    return t * t * t * (t * (t * 6 - 15) + 10)
}

func easeOutCubic(_ x: Double) -> Double {
    let t = clamp(x, 0, 1)
    return 1 - pow(1 - t, 3)
}

/// Rounds to the nearest even integer (video encoders require even dimensions).
func evenInt(_ v: Double) -> Int { max(2, Int((v / 2).rounded()) * 2) }

extension CGRect {
    /// Largest rect with the given aspect ratio (w/h) centred inside self.
    func aspectFit(aspect: CGFloat) -> CGRect {
        guard width > 0, height > 0, aspect > 0 else { return self }
        if width / height > aspect {
            let w = height * aspect
            return CGRect(x: midX - w / 2, y: minY, width: w, height: height)
        } else {
            let h = width / aspect
            return CGRect(x: minX, y: midY - h / 2, width: width, height: h)
        }
    }

    /// Smallest rect with the given aspect ratio covering self.
    func aspectFill(aspect: CGFloat) -> CGRect {
        guard width > 0, height > 0, aspect > 0 else { return self }
        if width / height > aspect {
            let h = width / aspect
            return CGRect(x: minX, y: midY - h / 2, width: width, height: h)
        } else {
            let w = height * aspect
            return CGRect(x: midX - w / 2, y: minY, width: w, height: height)
        }
    }
}

extension CMTime {
    init(sec: Double) { self = CMTime(seconds: sec, preferredTimescale: 60000) }
}

func formatTime(_ seconds: Double, fraction: Bool = false) -> String {
    let s = max(0, seconds.isFinite ? seconds : 0)
    let m = Int(s) / 60
    let r = s - Double(m * 60)
    if fraction {
        return String(format: "%d:%04.1f", m, r)
    }
    return String(format: "%d:%02d", m, Int(r))
}

extension Data {
    /// Cheap stable hash used to identify cursor images.
    var fnv1a: String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in self {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return String(h, radix: 16)
    }
}

/// Deep-merges `overlay` on top of `base` (used to decode settings saved by older versions).
func deepMerge(_ base: [String: Any], _ overlay: [String: Any]) -> [String: Any] {
    var out = base
    for (k, v) in overlay {
        if let b = base[k] as? [String: Any], let o = v as? [String: Any] {
            out[k] = deepMerge(b, o)
        } else {
            out[k] = v
        }
    }
    return out
}

/// Decodes `data` as T, filling any missing keys from `defaults`.
func decodeWithDefaults<T: Codable>(_ type: T.Type, from object: Any, defaults: T) -> T {
    guard let defData = try? JSONEncoder().encode(defaults),
          let defObj = try? JSONSerialization.jsonObject(with: defData) as? [String: Any],
          let obj = object as? [String: Any] else { return defaults }
    let merged = deepMerge(defObj, obj)
    guard let data = try? JSONSerialization.data(withJSONObject: merged),
          let value = try? JSONDecoder().decode(T.self, from: data) else { return defaults }
    return value
}
