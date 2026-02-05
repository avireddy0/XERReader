import XCTest
@testable import XERReader

final class XERParserTests: XCTestCase {
    var parser: XERParser!

    override func setUp() {
        super.setUp()
        parser = XERParser()
    }

    func testParsesSampleXER() throws {
        let xerContent = """
        ERMHDR\t20.12\t2024-01-15\tProject\tadmin
        %T\tPROJECT
        %F\tproj_id\tproj_short_name\tproj_name\tplan_start_date\tplan_end_date
        %R\t1000\tTEST\tTest Project\t2024-01-15 08:00\t2024-12-31 17:00
        %T\tTASK
        %F\ttask_id\tproj_id\twbs_id\ttask_code\ttask_name\ttask_type\tstatus_code\tphys_complete_pct\ttarget_start_date\ttarget_end_date\ttarget_drtn_hr_cnt\tremain_drtn_hr_cnt
        %R\t1001\t1000\t\tA1000\tTask One\tTT_Task\tTK_NotStart\t0\t2024-01-15 08:00\t2024-01-25 17:00\t80\t80
        %R\t1002\t1000\t\tA1010\tTask Two\tTT_Task\tTK_NotStart\t0\t2024-01-26 08:00\t2024-02-05 17:00\t80\t80
        %T\tTASKPRED
        %F\ttask_id\tpred_task_id\tpred_type\tlag_hr_cnt
        %R\t1002\t1001\tPR_FS\t0
        %E
        """

        let data = xerContent.data(using: .utf8)!
        let schedule = try parser.parse(data: data)

        // Verify project
        XCTAssertEqual(schedule.projects.count, 1)
        XCTAssertEqual(schedule.projects.first?.shortName, "TEST")
        XCTAssertEqual(schedule.projects.first?.name, "Test Project")

        // Verify tasks
        XCTAssertEqual(schedule.tasks.count, 2)
        XCTAssertEqual(schedule.tasks[0].taskCode, "A1000")
        XCTAssertEqual(schedule.tasks[1].taskCode, "A1010")

        // Verify relationships
        XCTAssertEqual(schedule.relationships.count, 1)
        XCTAssertEqual(schedule.relationships.first?.relationshipType, .finishToStart)
    }

    func testParsesTaskTypes() throws {
        let xerContent = """
        ERMHDR\t20.12\t2024-01-15\tProject\tadmin
        %T\tPROJECT
        %F\tproj_id\tproj_short_name
        %R\t1000\tTEST
        %T\tTASK
        %F\ttask_id\tproj_id\ttask_code\ttask_name\ttask_type\tstatus_code\tphys_complete_pct\ttarget_drtn_hr_cnt\tremain_drtn_hr_cnt
        %R\t1\t1000\tM1\tStart Milestone\tTT_Mile\tTK_NotStart\t0\t0\t0
        %R\t2\t1000\tT1\tRegular Task\tTT_Task\tTK_Active\t50\t80\t40
        %R\t3\t1000\tM2\tEnd Milestone\tTT_FinMile\tTK_NotStart\t0\t0\t0
        %E
        """

        let data = xerContent.data(using: .utf8)!
        let schedule = try parser.parse(data: data)

        XCTAssertEqual(schedule.tasks.count, 3)
        XCTAssertEqual(schedule.tasks[0].taskType, .startMilestone)
        XCTAssertEqual(schedule.tasks[1].taskType, .taskDependent)
        XCTAssertEqual(schedule.tasks[2].taskType, .finishMilestone)
    }

    func testParsesRelationshipTypes() throws {
        let xerContent = """
        ERMHDR\t20.12\t2024-01-15\tProject\tadmin
        %T\tPROJECT
        %F\tproj_id\tproj_short_name
        %R\t1000\tTEST
        %T\tTASK
        %F\ttask_id\tproj_id\ttask_code\ttask_name\ttask_type\tstatus_code\tphys_complete_pct\ttarget_drtn_hr_cnt\tremain_drtn_hr_cnt
        %R\t1\t1000\tT1\tTask 1\tTT_Task\tTK_NotStart\t0\t80\t80
        %R\t2\t1000\tT2\tTask 2\tTT_Task\tTK_NotStart\t0\t80\t80
        %R\t3\t1000\tT3\tTask 3\tTT_Task\tTK_NotStart\t0\t80\t80
        %R\t4\t1000\tT4\tTask 4\tTT_Task\tTK_NotStart\t0\t80\t80
        %T\tTASKPRED
        %F\ttask_id\tpred_task_id\tpred_type\tlag_hr_cnt
        %R\t2\t1\tPR_FS\t0
        %R\t3\t1\tPR_SS\t8
        %R\t4\t1\tPR_FF\t0
        %E
        """

        let data = xerContent.data(using: .utf8)!
        let schedule = try parser.parse(data: data)

        XCTAssertEqual(schedule.relationships.count, 3)
        XCTAssertEqual(schedule.relationships[0].relationshipType, .finishToStart)
        XCTAssertEqual(schedule.relationships[1].relationshipType, .startToStart)
        XCTAssertEqual(schedule.relationships[1].lagDays, 1.0) // 8 hours = 1 day
        XCTAssertEqual(schedule.relationships[2].relationshipType, .finishToFinish)
    }

    func testParsesResources() throws {
        let xerContent = """
        ERMHDR\t20.12\t2024-01-15\tProject\tadmin
        %T\tPROJECT
        %F\tproj_id\tproj_short_name
        %R\t1000\tTEST
        %T\tRSRC
        %F\trsrc_id\trsrc_short_name\trsrc_name\trsrc_type\tdef_qty_per_hr
        %R\t1\tPM\tProject Manager\tRT_Labor\t1
        %R\t2\tCRANE\tTower Crane\tRT_Equip\t1
        %R\t3\tCONC\tConcrete\tRT_Mat\t1
        %E
        """

        let data = xerContent.data(using: .utf8)!
        let schedule = try parser.parse(data: data)

        XCTAssertEqual(schedule.resources.count, 3)
        XCTAssertEqual(schedule.resources[0].resourceType, .labor)
        XCTAssertEqual(schedule.resources[1].resourceType, .nonLabor)
        XCTAssertEqual(schedule.resources[2].resourceType, .material)
    }

    func testEmptyFileThrowsError() {
        let data = Data()

        XCTAssertThrowsError(try parser.parse(data: data)) { error in
            XCTAssertEqual(error as? XERParseError, .encodingError)
        }
    }

    func testMissingProjectTableThrowsError() {
        let xerContent = """
        ERMHDR\t20.12\t2024-01-15\tProject\tadmin
        %T\tTASK
        %F\ttask_id\tproj_id\ttask_code\ttask_name
        %R\t1\t1000\tT1\tTask 1
        %E
        """

        let data = xerContent.data(using: .utf8)!

        XCTAssertThrowsError(try parser.parse(data: data)) { error in
            if case XERParseError.missingRequiredTable(let table) = error {
                XCTAssertEqual(table, "PROJECT")
            } else {
                XCTFail("Expected missingRequiredTable error")
            }
        }
    }
}

final class ScheduleAnalyzerTests: XCTestCase {
    func testCriticalPathIdentification() {
        var schedule = Schedule()

        schedule.projects = [
            Project(id: "1", shortName: "TEST", name: "Test")
        ]

        // Create tasks - task 2 has zero float (critical)
        var task1 = ScheduleTask(
            id: "1", projectId: "1", wbsId: nil, taskCode: "T1", name: "Task 1",
            taskType: .taskDependent, status: .notStarted, percentComplete: 0,
            targetStartDate: Date(), targetEndDate: Date().addingTimeInterval(86400 * 10),
            targetDuration: 80, remainingDuration: 80
        )
        task1.totalFloat = 40 // 5 days float

        var task2 = ScheduleTask(
            id: "2", projectId: "1", wbsId: nil, taskCode: "T2", name: "Task 2",
            taskType: .taskDependent, status: .notStarted, percentComplete: 0,
            targetStartDate: Date(), targetEndDate: Date().addingTimeInterval(86400 * 10),
            targetDuration: 80, remainingDuration: 80
        )
        task2.totalFloat = 0 // Critical

        schedule.tasks = [task1, task2]

        let analyzer = ScheduleAnalyzer(schedule: schedule)
        let result = analyzer.getCriticalPath()

        XCTAssertEqual(result.taskCount, 1)
        XCTAssertEqual(result.tasks.first?.taskCode, "T2")
    }

    func testLogicCheck() {
        var schedule = Schedule()

        schedule.projects = [
            Project(id: "1", shortName: "TEST", name: "Test")
        ]

        schedule.tasks = [
            ScheduleTask(
                id: "1", projectId: "1", wbsId: nil, taskCode: "T1", name: "No Predecessors",
                taskType: .taskDependent, status: .notStarted, percentComplete: 0,
                targetStartDate: Date(), targetEndDate: Date(),
                targetDuration: 80, remainingDuration: 80
            ),
            ScheduleTask(
                id: "2", projectId: "1", wbsId: nil, taskCode: "T2", name: "Has Predecessor",
                taskType: .taskDependent, status: .notStarted, percentComplete: 0,
                targetStartDate: Date(), targetEndDate: Date(),
                targetDuration: 80, remainingDuration: 80
            ),
            ScheduleTask(
                id: "3", projectId: "1", wbsId: nil, taskCode: "T3", name: "No Successors",
                taskType: .taskDependent, status: .notStarted, percentComplete: 0,
                targetStartDate: Date(), targetEndDate: Date(),
                targetDuration: 80, remainingDuration: 80
            )
        ]

        schedule.relationships = [
            Relationship(taskId: "2", predecessorTaskId: "1", relationshipType: .finishToStart),
            Relationship(taskId: "3", predecessorTaskId: "2", relationshipType: .finishToStart)
        ]

        let analyzer = ScheduleAnalyzer(schedule: schedule)
        let result = analyzer.checkLogic()

        // Task 1 has no predecessors (open start)
        XCTAssertEqual(result.openStarts.count, 1)
        XCTAssertEqual(result.openStarts.first?.taskCode, "T1")

        // Task 3 has no successors (open end)
        XCTAssertEqual(result.openEnds.count, 1)
        XCTAssertEqual(result.openEnds.first?.taskCode, "T3")
    }

    func testDCMACheck() {
        var schedule = Schedule()

        schedule.projects = [
            Project(id: "1", shortName: "TEST", name: "Test")
        ]

        // Create 10 tasks
        for i in 1...10 {
            schedule.tasks.append(ScheduleTask(
                id: "\(i)", projectId: "1", wbsId: nil, taskCode: "T\(i)", name: "Task \(i)",
                taskType: .taskDependent, status: .notStarted, percentComplete: 0,
                targetStartDate: Date(), targetEndDate: Date(),
                targetDuration: 40, remainingDuration: 40
            ))
        }

        // Create relationships (>1.5 per task for pass)
        for i in 2...10 {
            schedule.relationships.append(
                Relationship(taskId: "\(i)", predecessorTaskId: "\(i-1)", relationshipType: .finishToStart)
            )
        }

        let analyzer = ScheduleAnalyzer(schedule: schedule)
        let result = analyzer.performDCMACheck()

        XCTAssertGreaterThan(result.checks.count, 0)
        XCTAssertGreaterThanOrEqual(result.overallScore, 0)
        XCTAssertLessThanOrEqual(result.overallScore, 100)
    }
}
