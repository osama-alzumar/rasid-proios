import Foundation

// Lenient decoders for values Laravel/MySQL may send as either a number or a
// numeric string ("15.00", "3"). A present-but-unparseable value is treated as
// absent rather than failing the whole payload.
extension KeyedDecodingContainer {
    func flexibleInt(_ key: Key) throws -> Int {
        guard let value = try flexibleIntIfPresent(key) else {
            throw DecodingError.valueNotFound(Int.self, .init(codingPath: codingPath + [key], debugDescription: "Missing integer"))
        }
        return value
    }

    func flexibleIntIfPresent(_ key: Key) throws -> Int? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let int = try? decode(Int.self, forKey: key) { return int }
        if let double = try? decode(Double.self, forKey: key) { return Int(double) }
        if let string = try? decode(String.self, forKey: key) {
            let trimmed = string.trimmingCharacters(in: .whitespaces)
            return Int(trimmed) ?? Double(trimmed).map { Int($0) }
        }
        return nil
    }

    func flexibleDoubleIfPresent(_ key: Key) throws -> Double? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let double = try? decode(Double.self, forKey: key) { return double }
        if let string = try? decode(String.self, forKey: key) {
            return Double(string.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    func flexibleStringIfPresent(_ key: Key) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let string = try? decode(String.self, forKey: key) { return string }
        if let int = try? decode(Int.self, forKey: key) { return String(int) }
        return nil
    }
}
