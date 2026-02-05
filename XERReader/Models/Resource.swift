import Foundation

struct Resource: Codable, Equatable, Identifiable {
    let id: String
    let shortName: String
    let name: String
    let resourceType: ResourceType
    let unitOfMeasure: String?
    let defaultUnitsPerTime: Double

    init(id: String, shortName: String, name: String, resourceType: ResourceType,
         unitOfMeasure: String? = nil, defaultUnitsPerTime: Double = 1.0) {
        self.id = id
        self.shortName = shortName
        self.name = name.isEmpty ? shortName : name
        self.resourceType = resourceType
        self.unitOfMeasure = unitOfMeasure
        self.defaultUnitsPerTime = defaultUnitsPerTime
    }
}

enum ResourceType: String, Codable {
    case labor = "RT_Labor"
    case nonLabor = "RT_Equip"
    case material = "RT_Mat"

    init(rawP6Value: String) {
        switch rawP6Value {
        case "RT_Labor": self = .labor
        case "RT_Equip": self = .nonLabor
        case "RT_Mat": self = .material
        default: self = .labor
        }
    }

    var displayName: String {
        switch self {
        case .labor: return "Labor"
        case .nonLabor: return "Non-Labor"
        case .material: return "Material"
        }
    }
}

struct ResourceAssignment: Codable, Equatable, Identifiable {
    var id: String { "\(taskId)-\(resourceId)" }

    let taskId: String
    let resourceId: String
    let projectId: String
    let targetQuantity: Double
    let actualQuantity: Double
    let remainingQuantity: Double
    let targetCost: Double
    let actualCost: Double

    init(taskId: String, resourceId: String, projectId: String,
         targetQuantity: Double = 0, actualQuantity: Double = 0, remainingQuantity: Double = 0,
         targetCost: Double = 0, actualCost: Double = 0) {
        self.taskId = taskId
        self.resourceId = resourceId
        self.projectId = projectId
        self.targetQuantity = targetQuantity
        self.actualQuantity = actualQuantity
        self.remainingQuantity = remainingQuantity
        self.targetCost = targetCost
        self.actualCost = actualCost
    }
}
