import Foundation

/// Client-side pre-checks for a friendlier sign-up. The SERVER is the authority
/// (see username_problem() in the database); these checks only give instant feedback.
enum UsernameRules {
    static func formatProblem(_ raw: String) -> String? {
        let s = raw.lowercased()
        if s.count < 3 { return "At least 3 characters." }
        if s.count > 24 { return "At most 24 characters." }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.")
        if s.unicodeScalars.contains(where: { !allowed.contains($0) }) { return "Use letters, numbers, dots and underscores only." }
        if s.first == "." || s.first == "_" || s.last == "." || s.last == "_" { return "Must start and end with a letter or number." }
        if s.contains("..") || s.contains("__") || s.contains("._") || s.contains("_.") { return "No repeated dots or underscores." }
        return nil
    }

    /// Same normalisation idea as the server: NFKC, strip accents, undo leetspeak, collapse repeats.
    static func normalize(_ s: String) -> String {
        let folded = s.precomposedStringWithCompatibilityMapping
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .init(identifier: "en_US_POSIX"))
            .lowercased()
        let map: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s",
                                           "!": "i", "|": "l", "8": "b", "+": "t", "9": "g"]
        var out = ""
        for ch in folded {
            let c = map[ch] ?? ch
            guard c.isASCII, c.isLetter else { continue }
            if out.last != c { out.append(c) }
        }
        return out
    }

    static func passwordProblems(_ p: String) -> [String] {
        var issues: [String] = []
        if p.count < 8 { issues.append("8+ characters") }
        if p.rangeOfCharacter(from: .uppercaseLetters) == nil { issues.append("an uppercase letter") }
        if p.rangeOfCharacter(from: .lowercaseLetters) == nil { issues.append("a lowercase letter") }
        if p.rangeOfCharacter(from: .decimalDigits) == nil { issues.append("a number") }
        return issues
    }

    static func isValidEmail(_ e: String) -> Bool {
        e.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]{2,}$"#, options: .regularExpression) != nil
    }
}
