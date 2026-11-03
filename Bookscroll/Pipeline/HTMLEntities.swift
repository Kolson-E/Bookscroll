import Foundation

/// Decodes named and numeric HTML character references.
enum HTMLEntities {
    static func decode(_ input: String) -> String {
        guard input.contains("&") else { return input }
        let scalars = Array(input.unicodeScalars)
        var output = String.UnicodeScalarView()
        var i = 0
        while i < scalars.count {
            if scalars[i] == "&", let match = reference(in: scalars, at: i) {
                output.append(contentsOf: match.scalars)
                i += match.length
            } else {
                output.append(scalars[i])
                i += 1
            }
        }
        return String(output)
    }

    private static func reference(in s: [Unicode.Scalar], at start: Int) -> (scalars: [Unicode.Scalar], length: Int)? {
        let limit = min(s.count, start + 40)
        var j = start + 1
        while j < limit, s[j] != ";" {
            let v = s[j].value
            let isNameChar = (v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122) || v == 35
            if !isNameChar { return nil }
            j += 1
        }
        guard j < limit, s[j] == ";", j > start + 1 else { return nil }
        let body = String(String.UnicodeScalarView(s[(start + 1)..<j]))
        let length = j - start + 1
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value: UInt32?
            if let first = digits.first, first == "x" || first == "X" {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits, radix: 10)
            }
            guard let code = value else { return nil }
            return ([numericScalar(code)], length)
        }
        guard let replacement = named[body] else { return nil }
        return (Array(replacement.unicodeScalars), length)
    }

    /// Numeric references in 128...159 are Windows-1252 in practice (for example `&#151;`).
    private static func numericScalar(_ code: UInt32) -> Unicode.Scalar {
        if code >= 0x80 && code <= 0x9F, let mapped = windows1252[code], let scalar = Unicode.Scalar(mapped) {
            return scalar
        }
        if code == 0 { return "\u{FFFD}" }
        return Unicode.Scalar(code) ?? "\u{FFFD}"
    }

    private static let windows1252: [UInt32: UInt32] = [
        0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020,
        0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152,
        0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022,
        0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A,
        0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
    ]

    static let named: [String: String] = [
        // XML and basic HTML
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        // Latin-1 punctuation and symbols
        "iexcl": "\u{00A1}", "cent": "\u{00A2}", "pound": "\u{00A3}", "curren": "\u{00A4}",
        "yen": "\u{00A5}", "brvbar": "\u{00A6}", "sect": "\u{00A7}", "uml": "\u{00A8}",
        "copy": "\u{00A9}", "ordf": "\u{00AA}", "laquo": "\u{00AB}", "not": "\u{00AC}",
        "shy": "\u{00AD}", "reg": "\u{00AE}", "macr": "\u{00AF}", "deg": "\u{00B0}",
        "plusmn": "\u{00B1}", "sup2": "\u{00B2}", "sup3": "\u{00B3}", "acute": "\u{00B4}",
        "micro": "\u{00B5}", "para": "\u{00B6}", "middot": "\u{00B7}", "cedil": "\u{00B8}",
        "sup1": "\u{00B9}", "ordm": "\u{00BA}", "raquo": "\u{00BB}", "frac14": "\u{00BC}",
        "frac12": "\u{00BD}", "frac34": "\u{00BE}", "iquest": "\u{00BF}", "times": "\u{00D7}",
        "divide": "\u{00F7}",
        // Latin-1 letters
        "Agrave": "\u{00C0}", "Aacute": "\u{00C1}", "Acirc": "\u{00C2}", "Atilde": "\u{00C3}",
        "Auml": "\u{00C4}", "Aring": "\u{00C5}", "AElig": "\u{00C6}", "Ccedil": "\u{00C7}",
        "Egrave": "\u{00C8}", "Eacute": "\u{00C9}", "Ecirc": "\u{00CA}", "Euml": "\u{00CB}",
        "Igrave": "\u{00CC}", "Iacute": "\u{00CD}", "Icirc": "\u{00CE}", "Iuml": "\u{00CF}",
        "ETH": "\u{00D0}", "Ntilde": "\u{00D1}", "Ograve": "\u{00D2}", "Oacute": "\u{00D3}",
        "Ocirc": "\u{00D4}", "Otilde": "\u{00D5}", "Ouml": "\u{00D6}", "Oslash": "\u{00D8}",
        "Ugrave": "\u{00D9}", "Uacute": "\u{00DA}", "Ucirc": "\u{00DB}", "Uuml": "\u{00DC}",
        "Yacute": "\u{00DD}", "THORN": "\u{00DE}", "szlig": "\u{00DF}", "agrave": "\u{00E0}",
        "aacute": "\u{00E1}", "acirc": "\u{00E2}", "atilde": "\u{00E3}", "auml": "\u{00E4}",
        "aring": "\u{00E5}", "aelig": "\u{00E6}", "ccedil": "\u{00E7}", "egrave": "\u{00E8}",
        "eacute": "\u{00E9}", "ecirc": "\u{00EA}", "euml": "\u{00EB}", "igrave": "\u{00EC}",
        "iacute": "\u{00ED}", "icirc": "\u{00EE}", "iuml": "\u{00EF}", "eth": "\u{00F0}",
        "ntilde": "\u{00F1}", "ograve": "\u{00F2}", "oacute": "\u{00F3}", "ocirc": "\u{00F4}",
        "otilde": "\u{00F5}", "ouml": "\u{00F6}", "oslash": "\u{00F8}", "ugrave": "\u{00F9}",
        "uacute": "\u{00FA}", "ucirc": "\u{00FB}", "uuml": "\u{00FC}", "yacute": "\u{00FD}",
        "thorn": "\u{00FE}", "yuml": "\u{00FF}",
        // Latin Extended
        "OElig": "\u{0152}", "oelig": "\u{0153}", "Scaron": "\u{0160}", "scaron": "\u{0161}",
        "Yuml": "\u{0178}", "fnof": "\u{0192}", "circ": "\u{02C6}", "tilde": "\u{02DC}",
        // General punctuation
        "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}", "zwnj": "\u{200C}",
        "zwj": "\u{200D}", "lrm": "\u{200E}", "rlm": "\u{200F}", "ndash": "\u{2013}",
        "mdash": "\u{2014}", "lsquo": "\u{2018}", "rsquo": "\u{2019}", "sbquo": "\u{201A}",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "bdquo": "\u{201E}", "dagger": "\u{2020}",
        "Dagger": "\u{2021}", "bull": "\u{2022}", "hellip": "\u{2026}", "permil": "\u{2030}",
        "prime": "\u{2032}", "Prime": "\u{2033}", "lsaquo": "\u{2039}", "rsaquo": "\u{203A}",
        "oline": "\u{203E}", "frasl": "\u{2044}", "euro": "\u{20AC}", "trade": "\u{2122}",
        "larr": "\u{2190}", "uarr": "\u{2191}", "rarr": "\u{2192}", "darr": "\u{2193}",
        "harr": "\u{2194}", "minus": "\u{2212}", "infin": "\u{221E}", "ne": "\u{2260}",
        "le": "\u{2264}", "ge": "\u{2265}", "asymp": "\u{2248}", "loz": "\u{25CA}",
        "spades": "\u{2660}", "clubs": "\u{2663}", "hearts": "\u{2665}", "diams": "\u{2666}",
        // Greek
        "Alpha": "\u{0391}", "Beta": "\u{0392}", "Gamma": "\u{0393}", "Delta": "\u{0394}",
        "Epsilon": "\u{0395}", "Zeta": "\u{0396}", "Eta": "\u{0397}", "Theta": "\u{0398}",
        "Iota": "\u{0399}", "Kappa": "\u{039A}", "Lambda": "\u{039B}", "Mu": "\u{039C}",
        "Nu": "\u{039D}", "Xi": "\u{039E}", "Omicron": "\u{039F}", "Pi": "\u{03A0}",
        "Rho": "\u{03A1}", "Sigma": "\u{03A3}", "Tau": "\u{03A4}", "Upsilon": "\u{03A5}",
        "Phi": "\u{03A6}", "Chi": "\u{03A7}", "Psi": "\u{03A8}", "Omega": "\u{03A9}",
        "alpha": "\u{03B1}", "beta": "\u{03B2}", "gamma": "\u{03B3}", "delta": "\u{03B4}",
        "epsilon": "\u{03B5}", "zeta": "\u{03B6}", "eta": "\u{03B7}", "theta": "\u{03B8}",
        "iota": "\u{03B9}", "kappa": "\u{03BA}", "lambda": "\u{03BB}", "mu": "\u{03BC}",
        "nu": "\u{03BD}", "xi": "\u{03BE}", "omicron": "\u{03BF}", "pi": "\u{03C0}",
        "rho": "\u{03C1}", "sigmaf": "\u{03C2}", "sigma": "\u{03C3}", "tau": "\u{03C4}",
        "upsilon": "\u{03C5}", "phi": "\u{03C6}", "chi": "\u{03C7}", "psi": "\u{03C8}",
        "omega": "\u{03C9}",
    ]
}
