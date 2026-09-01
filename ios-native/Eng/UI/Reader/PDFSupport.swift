import Foundation
import PDFKit

/// Small PDFKit helpers shared by import and the reader.
enum PDFDocumentInfo {
    static func pageCount(at url: URL) -> Int { PDFDocument(url: url)?.pageCount ?? 0 }
}
