import Foundation
import UniformTypeIdentifiers

/// Parser for Microsoft Project files (.mpp, .xml)
/// MPP files are OLE compound documents - we support the XML export format
/// and can attempt to extract data from MPP via embedded XML streams
struct MPPParser {
    // MARK: - Constants for DoS Prevention
    static let maxFileSizeBytes = 100 * 1024 * 1024 // 100 MB
    static let maxTaskCount = 500_000

    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let alternateDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    func parse(data: Data) throws -> Schedule {
        // Security: Check file size to prevent DoS
        let fileSizeMB = data.count / (1024 * 1024)
        if data.count > Self.maxFileSizeBytes {
            throw MPPParseError.fileTooLarge(sizeMB: fileSizeMB, maxMB: Self.maxFileSizeBytes / (1024 * 1024))
        }

        // Try to detect file type
        if isXMLFormat(data) {
            return try parseXML(data: data)
        } else if isMPPFormat(data) {
            return try parseMPP(data: data)
        } else {
            throw MPPParseError.unsupportedFormat
        }
    }

    // MARK: - Format Detection

    private func isXMLFormat(_ data: Data) -> Bool {
        guard let header = String(data: data.prefix(100), encoding: .utf8) else { return false }
        return header.contains("<?xml") || header.contains("<Project")
    }

    private func isMPPFormat(_ data: Data) -> Bool {
        // MPP files start with OLE compound document signature
        let oleSignature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
        guard data.count >= 8 else { return false }
        let header = [UInt8](data.prefix(8))
        return header == oleSignature
    }

    // MARK: - XML Parsing (Microsoft Project XML format)

    private func parseXML(data: Data) throws -> Schedule {
        let parser = MSProjectXMLParser()
        return try parser.parse(data: data)
    }

    // MARK: - MPP Binary Parsing

    private func parseMPP(data: Data) throws -> Schedule {
        // MPP is an OLE compound document format
        // We'll attempt to find embedded XML or extract key data
        // For full MPP support, a more sophisticated parser would be needed

        // Check for embedded XML stream
        if let xmlData = extractEmbeddedXML(from: data) {
            return try parseXML(data: xmlData)
        }

        // Try to parse as simple MPP structure
        return try parseSimpleMPP(data: data)
    }

    private func extractEmbeddedXML(from data: Data) -> Data? {
        // Look for XML markers in the binary data
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            return nil
        }

        if let xmlStart = content.range(of: "<?xml"),
           let xmlEnd = content.range(of: "</Project>") {
            let xmlString = String(content[xmlStart.lowerBound..<xmlEnd.upperBound])
            return xmlString.data(using: .utf8)
        }

        return nil
    }

    private func parseSimpleMPP(data: Data) throws -> Schedule {
        // Basic MPP structure extraction
        // This is a simplified parser - full MPP support requires
        // parsing the OLE compound document structure

        var schedule = Schedule()

        // Try to extract project name from various locations
        if let projectName = extractString(from: data, marker: "Title") {
            schedule.projects.append(Project(
                id: "1",
                shortName: projectName,
                name: projectName
            ))
        } else {
            schedule.projects.append(Project(
                id: "1",
                shortName: "Imported Project",
                name: "Imported Project"
            ))
        }

        throw MPPParseError.binaryFormatNotFullySupported
    }

    private func extractString(from data: Data, marker: String) -> String? {
        guard let content = String(data: data, encoding: .utf16) else { return nil }
        // Simple extraction - look for marker followed by string
        if let range = content.range(of: marker) {
            let afterMarker = content[range.upperBound...]
            let endIndex = afterMarker.firstIndex(of: "\0") ?? afterMarker.endIndex
            return String(afterMarker[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

// MARK: - Microsoft Project XML Parser

class MSProjectXMLParser: NSObject, XMLParserDelegate {
    private var schedule = Schedule()
    private var currentElement = ""
    private var currentTask: TaskBuilder?
    private var currentRelationship: RelationshipBuilder?
    private var currentResource: ResourceBuilder?
    private var currentAssignment: AssignmentBuilder?
    private var currentCalendar: CalendarBuilder?
    private var currentProject: ProjectBuilder?
    private var textBuffer = ""

    private var taskIdMap: [String: String] = [:] // UID -> our ID

    func parse(data: Data) throws -> Schedule {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        // Security: Explicitly disable external entity resolution to prevent XXE attacks
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            throw MPPParseError.xmlParsingFailed(parser.parserError?.localizedDescription ?? "Unknown error")
        }

        return schedule
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        textBuffer = ""

        switch elementName {
        case "Project":
            currentProject = ProjectBuilder()
        case "Task":
            currentTask = TaskBuilder()
        case "Resource":
            currentResource = ResourceBuilder()
        case "Assignment":
            currentAssignment = AssignmentBuilder()
        case "Calendar":
            currentCalendar = CalendarBuilder()
        case "PredecessorLink":
            currentRelationship = RelationshipBuilder()
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle shared elements that apply to multiple contexts
        if handleSharedElement(elementName, text: text) { return }

        // Handle entity-specific elements
        switch elementName {
        case "Project", "Title", "StartDate", "FinishDate":
            handleProjectElement(elementName, text: text)
        case "Task", "ID", "Start", "Finish", "Duration", "PercentComplete",
             "Critical", "Milestone", "Summary", "WBS", "OutlineLevel", "TotalSlack":
            handleTaskElement(elementName, text: text)
        case "PredecessorLink", "PredecessorUID", "Type", "LinkLag":
            handleRelationshipElement(elementName, text: text)
        case "Resource":
            handleResourceElement(elementName, text: text)
        case "Assignment", "TaskUID", "ResourceUID", "Units":
            handleAssignmentElement(elementName, text: text)
        default:
            break
        }
    }

    // MARK: - Element Handlers

    /// Handle elements that can apply to multiple entity types (UID, Name)
    private func handleSharedElement(_ elementName: String, text: String) -> Bool {
        switch elementName {
        case "UID":
            if currentTask != nil {
                currentTask?.uid = text
            } else if currentRelationship != nil {
                currentRelationship?.predecessorUID = text
            } else if currentResource != nil {
                currentResource?.uid = text
            }
            return true
        case "Name":
            if currentTask != nil {
                currentTask?.name = text
            } else if currentResource != nil {
                currentResource?.name = text
            } else if currentCalendar != nil {
                currentCalendar?.name = text
            }
            return true
        default:
            return false
        }
    }

    private func handleProjectElement(_ elementName: String, text: String) {
        switch elementName {
        case "Title":
            currentProject?.name = text
        case "StartDate":
            currentProject?.startDate = parseDate(text)
        case "FinishDate":
            currentProject?.endDate = parseDate(text)
        case "Project":
            if let builder = currentProject {
                schedule.projects.append(builder.build())
            }
            currentProject = nil
        default:
            break
        }
    }

    private func handleTaskElement(_ elementName: String, text: String) {
        switch elementName {
        case "ID":
            currentTask?.id = text
        case "Start":
            currentTask?.startDate = parseDate(text)
        case "Finish":
            currentTask?.endDate = parseDate(text)
        case "Duration":
            currentTask?.duration = parseDuration(text)
        case "PercentComplete":
            currentTask?.percentComplete = Double(text) ?? 0
        case "Critical":
            currentTask?.isCritical = text == "1"
        case "Milestone":
            currentTask?.isMilestone = text == "1"
        case "Summary":
            currentTask?.isSummary = text == "1"
        case "WBS":
            currentTask?.wbs = text
        case "OutlineLevel":
            currentTask?.outlineLevel = Int(text) ?? 1
        case "TotalSlack":
            currentTask?.totalSlack = parseDuration(text)
        case "Task":
            if let builder = currentTask, !builder.isSummary {
                let task = builder.build()
                schedule.tasks.append(task)
                if let uid = builder.uid {
                    taskIdMap[uid] = task.id
                }
            }
            currentTask = nil
        default:
            break
        }
    }

    private func handleRelationshipElement(_ elementName: String, text: String) {
        switch elementName {
        case "PredecessorUID":
            currentRelationship?.predecessorUID = text
        case "Type":
            currentRelationship?.type = Int(text) ?? 1
        case "LinkLag":
            currentRelationship?.lag = parseDuration(text)
        case "PredecessorLink":
            if let builder = currentRelationship, let taskUID = currentTask?.uid {
                if let relationship = builder.build(taskUID: taskUID, taskIdMap: taskIdMap) {
                    schedule.relationships.append(relationship)
                }
            }
            currentRelationship = nil
        default:
            break
        }
    }

    private func handleResourceElement(_ elementName: String, text: String) {
        if elementName == "Resource" {
            if let builder = currentResource {
                schedule.resources.append(builder.build())
            }
            currentResource = nil
        }
    }

    private func handleAssignmentElement(_ elementName: String, text: String) {
        switch elementName {
        case "TaskUID":
            currentAssignment?.taskUID = text
        case "ResourceUID":
            currentAssignment?.resourceUID = text
        case "Units":
            currentAssignment?.units = Double(text) ?? 1.0
        case "Assignment":
            if let builder = currentAssignment {
                if let assignment = builder.build(taskIdMap: taskIdMap) {
                    schedule.resourceAssignments.append(assignment)
                }
            }
            currentAssignment = nil
        default:
            break
        }
    }

    // MARK: - Helpers

    private func parseDate(_ string: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: string) {
            return date
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: string)
    }

    private func parseDuration(_ string: String) -> Double {
        // MS Project duration format: PT8H0M0S (ISO 8601 duration)
        var hours: Double = 0

        if string.hasPrefix("PT") {
            let duration = String(string.dropFirst(2))

            if let hRange = duration.range(of: "H") {
                let hValue = duration[..<hRange.lowerBound]
                hours = Double(hValue) ?? 0
            }

            if let mRange = duration.range(of: "M") {
                let startIndex = duration.range(of: "H")?.upperBound ?? duration.startIndex
                let mValue = duration[startIndex..<mRange.lowerBound]
                hours += (Double(mValue) ?? 0) / 60
            }
        }

        return hours
    }
}

// MARK: - Builder Classes

private class ProjectBuilder {
    var name: String = "Untitled"
    var startDate: Date?
    var endDate: Date?

    func build() -> Project {
        Project(
            id: "1",
            shortName: name,
            name: name,
            planStartDate: startDate,
            planEndDate: endDate
        )
    }
}

private class TaskBuilder {
    var uid: String?
    var id: String?
    var name: String = ""
    var startDate: Date?
    var endDate: Date?
    var duration: Double = 0
    var percentComplete: Double = 0
    var isCritical: Bool = false
    var isMilestone: Bool = false
    var isSummary: Bool = false
    var wbs: String?
    var outlineLevel: Int = 1
    var totalSlack: Double = 0

    func build() -> ScheduleTask {
        let taskId = id ?? uid ?? UUID().uuidString
        var task = ScheduleTask(
            id: taskId,
            projectId: "1",
            wbsId: nil,
            taskCode: wbs ?? "A\(taskId)",
            name: name,
            taskType: isMilestone ? .startMilestone : .taskDependent,
            status: percentComplete >= 100 ? .complete : (percentComplete > 0 ? .active : .notStarted),
            percentComplete: percentComplete,
            targetStartDate: startDate,
            targetEndDate: endDate,
            targetDuration: duration,
            remainingDuration: duration * (1 - percentComplete / 100)
        )
        task.totalFloat = totalSlack
        return task
    }
}

private class RelationshipBuilder {
    var predecessorUID: String?
    var type: Int = 1 // 0=FF, 1=FS, 2=SF, 3=SS
    var lag: Double = 0

    func build(taskUID: String, taskIdMap: [String: String]) -> Relationship? {
        guard let predUID = predecessorUID,
              let predId = taskIdMap[predUID],
              let taskId = taskIdMap[taskUID] else {
            return nil
        }

        let relType: RelationshipType
        switch type {
        case 0: relType = .finishToFinish
        case 1: relType = .finishToStart
        case 2: relType = .startToFinish
        case 3: relType = .startToStart
        default: relType = .finishToStart
        }

        return Relationship(
            taskId: taskId,
            predecessorTaskId: predId,
            relationshipType: relType,
            lagDays: lag / 8 // Convert hours to days
        )
    }
}

private class ResourceBuilder {
    var uid: String?
    var name: String = ""

    func build() -> Resource {
        Resource(
            id: uid ?? UUID().uuidString,
            shortName: name,
            name: name,
            resourceType: .labor
        )
    }
}

private class AssignmentBuilder {
    var taskUID: String?
    var resourceUID: String?
    var units: Double = 1.0

    func build(taskIdMap: [String: String]) -> ResourceAssignment? {
        guard let tUID = taskUID,
              let rUID = resourceUID,
              let taskId = taskIdMap[tUID] else {
            return nil
        }

        return ResourceAssignment(
            taskId: taskId,
            resourceId: rUID,
            projectId: "1",
            targetQuantity: units
        )
    }
}

private class CalendarBuilder {
    var name: String = ""

    func build() -> WorkCalendar {
        WorkCalendar(
            id: UUID().uuidString,
            name: name
        )
    }
}

// MARK: - Errors

enum MPPParseError: LocalizedError {
    case unsupportedFormat
    case xmlParsingFailed(String)
    case binaryFormatNotFullySupported
    case fileTooLarge(sizeMB: Int, maxMB: Int)
    case tooManyTasks(count: Int, max: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported file format. Please use .xml export from Microsoft Project."
        case .xmlParsingFailed(let reason):
            return "Failed to parse XML: \(reason)"
        case .binaryFormatNotFullySupported:
            return "Binary MPP format not fully supported. Please export to XML from Microsoft Project."
        case .fileTooLarge(let sizeMB, let maxMB):
            return "File is too large (\(sizeMB)MB). Maximum supported size is \(maxMB)MB"
        case .tooManyTasks(let count, let max):
            return "File contains too many tasks (\(count)). Maximum supported is \(max)"
        }
    }
}

// MARK: - UTType Extension

extension UTType {
    static var mpp: UTType {
        UTType(importedAs: "com.microsoft.project", conformingTo: .data)
    }

    static var msProjectXML: UTType {
        UTType(importedAs: "com.microsoft.project.xml", conformingTo: .xml)
    }
}
