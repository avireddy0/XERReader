import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var xer: UTType {
        UTType(importedAs: "com.oracle.primavera.xer", conformingTo: .data)
    }
}

struct XERDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xer, .mpp, .msProjectXML, .xml, .plainText] }

    var schedule: Schedule

    init() {
        self.schedule = Schedule()
    }

    init(schedule: Schedule) {
        self.schedule = schedule
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw XERParseError.emptyFile
        }

        // Determine file type and use appropriate parser
        let filename = configuration.file.filename ?? ""
        let ext = (filename as NSString).pathExtension.lowercased()

        if ext == "mpp" || ext == "xml" || configuration.contentType == .mpp || configuration.contentType == .msProjectXML {
            // Try MPP/XML parser first
            do {
                self.schedule = try MPPParser().parse(data: data)
                return
            } catch let mppError {
                // Log the MPP error and try XER as fallback
                print("[XERDocument] MPP parsing failed: \(mppError.localizedDescription), attempting XER format...")

                // Try XER parser as fallback
                do {
                    self.schedule = try XERParser().parse(data: data)
                    return
                } catch {
                    // Both parsers failed - throw the original MPP error as it was the expected format
                    throw ScheduleParseError.mppParsingFailed(
                        reason: mppError.localizedDescription,
                        xerFallbackError: error.localizedDescription
                    )
                }
            }
        }

        // Default to XER parser
        self.schedule = try XERParser().parse(data: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Export as JSON for now (XER writing not implemented)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(schedule)
        return FileWrapper(regularFileWithContents: data)
    }
}

enum XERParseError: LocalizedError {
    case emptyFile
    case invalidFormat
    case missingHeader
    case encodingError
    case missingRequiredTable(String)
    case fileTooLarge(sizeMB: Int, maxMB: Int)
    case tooManyRows(count: Int, max: Int)

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The file is empty"
        case .invalidFormat:
            return "The file is not a valid XER format"
        case .missingHeader:
            return "Missing ERMHDR header"
        case .encodingError:
            return "Could not decode file contents"
        case .missingRequiredTable(let table):
            return "Missing required table: \(table)"
        case .fileTooLarge(let sizeMB, let maxMB):
            return "File is too large (\(sizeMB)MB). Maximum supported size is \(maxMB)MB"
        case .tooManyRows(let count, let max):
            return "File contains too many rows (\(count)). Maximum supported is \(max)"
        }
    }
}

enum ScheduleParseError: LocalizedError {
    case mppParsingFailed(reason: String, xerFallbackError: String)
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .mppParsingFailed(let reason, let xerFallback):
            return "Failed to parse Microsoft Project file: \(reason). XER fallback also failed: \(xerFallback)"
        case .unsupportedFormat(let format):
            return "Unsupported file format: \(format)"
        }
    }
}
