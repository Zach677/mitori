import Foundation

enum BalanceParser {
    static func parse(plistData: Data, source: BalanceSnapshot.Source) throws -> BalanceSnapshot {
        let rootObject = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)

        if let candidate = explicitCandidate(in: rootObject) ?? recursiveCandidate(in: rootObject, path: []) {
            return BalanceSnapshot(
                displayText: candidate.displayText,
                numericValue: candidate.numericValue,
                currencyCode: candidate.currencyCode,
                fetchedAt: Date(),
                source: source,
                rawFieldPath: candidate.path
            )
        }

        throw MitoriError.balanceNotFound
    }
}

private extension BalanceParser {
    struct Candidate {
        var displayText: String
        var numericValue: Decimal?
        var currencyCode: String?
        var path: String
    }

    enum PathComponent {
        case key(String)
        case index(Int)
    }

    static let explicitPaths: [[PathComponent]] = [
        [.key("creditDisplay")],
        [.key("creditBalance")],
        [.key("balance")],
        [.key("accountInfo"), .key("creditDisplay")],
        [.key("accountInfo"), .key("creditBalance")],
        [.key("accountInfo"), .key("balance")],
        [.key("songList"), .index(0), .key("creditDisplay")],
        [.key("songList"), .index(0), .key("creditBalance")],
        [.key("songList"), .index(0), .key("balance")],
        [.key("songList"), .index(0), .key("metadata"), .key("creditDisplay")],
        [.key("songList"), .index(0), .key("metadata"), .key("creditBalance")],
        [.key("songList"), .index(0), .key("metadata"), .key("balance")],
    ]

    static func explicitCandidate(in rootObject: Any) -> Candidate? {
        for path in explicitPaths {
            if let value = value(at: path, in: rootObject),
               let candidate = candidate(from: value, path: render(path), force: true)
            {
                return candidate
            }
        }
        return nil
    }

    static func recursiveCandidate(in value: Any, path: [String]) -> Candidate? {
        if let dictionary = value as? [String: Any] {
            for key in dictionary.keys.sorted() {
                let child = dictionary[key] as Any
                let nextPath = path + [key]
                let lowercasedKey = key.lowercased()
                if lowercasedKey.contains("balance") || lowercasedKey.contains("credit"),
                   let candidate = candidate(from: child, path: nextPath.joined(separator: "."), force: true)
                {
                    return candidate
                }
                if let candidate = recursiveCandidate(in: child, path: nextPath) {
                    return candidate
                }
            }
        }

        if let array = value as? [Any] {
            for (index, child) in array.enumerated() {
                var nextPath = path
                nextPath.append("[\(index)]")
                if let candidate = recursiveCandidate(in: child, path: nextPath) {
                    return candidate
                }
            }
        }

        return nil
    }

    static func value(at path: [PathComponent], in rootObject: Any) -> Any? {
        var current: Any? = rootObject
        for component in path {
            switch component {
            case let .key(key):
                current = (current as? [String: Any])?[key]
            case let .index(index):
                guard let array = current as? [Any], array.indices.contains(index) else {
                    return nil
                }
                current = array[index]
            }
        }
        return current
    }

    static func render(_ path: [PathComponent]) -> String {
        path.map { component in
            switch component {
            case let .key(key):
                return key
            case let .index(index):
                return "[\(index)]"
            }
        }
        .joined(separator: ".")
        .replacingOccurrences(of: ".[", with: "[")
    }

    static func candidate(from value: Any, path: String, force: Bool) -> Candidate? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if !force, numericValue(from: trimmed) == nil, currencyCode(from: trimmed) == nil {
                return nil
            }
            return Candidate(
                displayText: trimmed,
                numericValue: numericValue(from: trimmed),
                currencyCode: currencyCode(from: trimmed),
                path: path
            )

        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return nil
            }
            let decimal = Decimal(string: number.stringValue)
            return Candidate(
                displayText: number.stringValue,
                numericValue: decimal,
                currencyCode: nil,
                path: path
            )

        case let dictionary as [String: Any]:
            return candidate(from: dictionary, path: path)

        case let array as [Any]:
            for (index, child) in array.enumerated() {
                if let candidate = candidate(from: child, path: "\(path)[\(index)]", force: force) {
                    return candidate
                }
            }
            return nil

        default:
            return nil
        }
    }

    static func candidate(from dictionary: [String: Any], path: String) -> Candidate? {
        let displayKeys = ["display", "formatted", "formattedValue", "text", "value", "creditDisplay"]
        let amountKeys = ["amount", "numericValue", "creditBalance", "balance", "value"]
        let currencyKeys = ["currency", "currencyCode", "isoCurrencyCode"]

        let display = firstString(for: displayKeys, in: dictionary)
        let amount = firstDecimal(for: amountKeys, in: dictionary)
        let currency = firstString(for: currencyKeys, in: dictionary)

        if let display {
            return Candidate(
                displayText: display,
                numericValue: amount ?? numericValue(from: display),
                currencyCode: currency ?? currencyCode(from: display),
                path: path
            )
        }

        if let amount {
            let renderedAmount = NSDecimalNumber(decimal: amount).stringValue
            let displayText = currency.map { "\($0) \(renderedAmount)" } ?? renderedAmount
            return Candidate(
                displayText: displayText,
                numericValue: amount,
                currencyCode: currency,
                path: path
            )
        }

        return nil
    }

    static func firstString(for keys: [String], in dictionary: [String: Any]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    static func firstDecimal(for keys: [String], in dictionary: [String: Any]) -> Decimal? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    continue
                }
                return Decimal(string: number.stringValue)
            }
            if let string = value as? String, let decimal = numericValue(from: string) {
                return decimal
            }
            if let nestedDictionary = value as? [String: Any],
               let decimal = firstDecimal(for: ["amount", "value"], in: nestedDictionary)
            {
                return decimal
            }
        }
        return nil
    }

    static func numericValue(from text: String) -> Decimal? {
        let fragments = text
            .components(separatedBy: CharacterSet(charactersIn: "0123456789,.-").inverted)
            .filter { $0.contains(where: \.isNumber) }

        guard var candidate = fragments.max(by: { $0.count < $1.count }) else {
            return nil
        }

        if candidate.contains(",") && candidate.contains(".") {
            if let lastComma = candidate.lastIndex(of: ","),
               let lastDot = candidate.lastIndex(of: ".")
            {
                if lastComma > lastDot {
                    candidate = candidate.replacingOccurrences(of: ".", with: "")
                    candidate = candidate.replacingOccurrences(of: ",", with: ".")
                } else {
                    candidate = candidate.replacingOccurrences(of: ",", with: "")
                }
            }
        } else if candidate.contains(",") {
            candidate = candidate.replacingOccurrences(of: ",", with: ".")
        }

        return Decimal(string: candidate, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func currencyCode(from text: String) -> String? {
        guard let range = text.range(of: #"\b[A-Z]{3}\b"#, options: .regularExpression) else {
            return nil
        }
        return String(text[range])
    }
}
