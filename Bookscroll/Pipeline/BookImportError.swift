import Foundation

enum BookImportError: LocalizedError, Equatable {
    case unsupportedFormat
    case unreadable(String)
    case drmProtected
    case passwordProtected
    case scannedPDF
    case noText
    case duplicate(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "This is not an EPUB or PDF file."
        case let .unreadable(detail):
            return "The file could not be read. \(detail)"
        case .drmProtected:
            return "This book is DRM-protected. Bookscroll can only import DRM-free EPUB and PDF files."
        case .passwordProtected:
            return "This PDF is password-protected or encrypted. Bookscroll can only import unlocked files."
        case .scannedPDF:
            return "This PDF has no text layer. It looks like a scan, so there is no text to show."
        case .noText:
            return "No readable text was found in this book."
        case let .duplicate(title):
            return "\u{201C}\(title)\u{201D} is already in your library."
        }
    }
}
