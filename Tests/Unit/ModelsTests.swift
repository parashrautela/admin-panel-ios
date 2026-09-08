import XCTest
@testable import AdminPanel

final class ModelsTests: XCTestCase {
    func testUnknownStatusNeverBecomesPending() throws {
        let row = try JSONDecoder().decode(Submission.self, from: Data(#"{"id":"sample","verification_status":"future_status"}"#.utf8))
        XCTAssertEqual(row.status, .unknown)
        XCTAssertFalse(row.status.actionable)
        let missing = try JSONDecoder().decode(Submission.self, from: Data(#"{"id":"sample"}"#.utf8))
        XCTAssertEqual(missing.status, .unknown)
    }
    func testWhitespaceAndMissingDatesHaveHonestFallbacks() throws {
        let row = try JSONDecoder().decode(Submission.self, from: Data(#"{"id":"sample","full_name":"   ","city":" ","state":" Delhi ","aadhar_number":"123456781234"}"#.utf8))
        XCTAssertEqual(row.displayName, "Name not provided")
        XCTAssertEqual(row.location, "Delhi")
        XCTAssertEqual(row.maskedAadhaar, "•••• •••• 1234")
        XCTAssertEqual(row.submittedDateTimeText, "Time unavailable")
        XCTAssertNil(Submission.date("2026-09-08T12:00:00"))
        XCTAssertNotNil(Submission.date("2026-09-08T12:00:00.123456+05:30"))
    }
    func testApprovalRequiresEveryAvailableDocumentToPass() {
        let docs = [EvidenceDocument(id: "pan", kind: "pan_card", filename: "pan.pdf", available: true)]
        var draft = DecisionDraft()
        draft.reason = "All checks passed"; draft.message = "Application approved"; draft.confirmed = true
        XCTAssertNotNil(draft.validation(required: docs, status: .pending))
        draft.assessments = ["pan_card": "pass"]
        XCTAssertNil(draft.validation(required: docs, status: .pending))
        XCTAssertNotNil(draft.validation(required: [], status: .pending))
        XCTAssertNotNil(draft.validation(required: docs, status: .unknown))
        XCTAssertNotNil(draft.validation(required: docs, status: .banned))
        var missing = docs; missing[0].available = false
        XCTAssertNotNil(draft.validation(required: missing, status: .pending))
    }
    func testHoldResubmissionAndConfirmationValidation() {
        var draft = DecisionDraft(); draft.outcome = .hold; draft.reason = "Need manual check"
        XCTAssertNotNil(draft.validation(required: [], status: .pending))
        draft.confirmed = true
        XCTAssertNil(draft.validation(required: [], status: .pending))
        draft.followUp = .distantPast
        XCTAssertNotNil(draft.validation(required: [], status: .pending))
        draft.outcome = .resubmit; draft.message = "Please replace PAN"
        XCTAssertNotNil(draft.validation(required: [], status: .pending))
        draft.documents = ["pan_card"]
        XCTAssertNil(draft.validation(required: [], status: .pending))
    }
    @MainActor func testPreviewPaginationAndIdempotentDecision() throws {
        let store = PreviewStore()
        let first = store.queue(.wholesaler, status: nil, search: "", sort: "oldest", ownership: "all", cursor: nil)
        let second = store.queue(.wholesaler, status: nil, search: "", sort: "oldest", ownership: "all", cursor: first.next_cursor)
        XCTAssertEqual(first.rows.count, 30); XCTAssertEqual(first.total, 65)
        XCTAssertTrue(Set(first.rows.map(\.id)).isDisjoint(with: Set(second.rows.map(\.id))))
        let row = first.rows[0]
        var draft = DecisionDraft(); draft.outcome = .hold; draft.reason = "Waiting for clarification"; draft.confirmed = true
        let receipt = try store.decide(.wholesaler, submission: row, draft: draft)
        let replay = try store.decide(.wholesaler, submission: row, draft: draft)
        XCTAssertEqual(receipt.event_id, replay.event_id)
        draft.requestID = UUID().uuidString
        XCTAssertThrowsError(try store.decide(.wholesaler, submission: row, draft: draft))
    }
    @MainActor func testEntitySwitchClearsPreviousScopeImmediately() async {
        let previous = AdminAPI.shared.preview; AdminAPI.shared.preview = true
        defer { AdminAPI.shared.preview = previous }
        let queue = QueueStore(); await queue.refresh()
        XCTAssertFalse(queue.rows.isEmpty)
        queue.entity = .retailer
        XCTAssertTrue(queue.rows.isEmpty); XCTAssertNil(queue.counts); XCTAssertNil(queue.cursor)
        await queue.refresh()
        XCTAssertTrue(queue.rows.first?.id.hasSuffix("101") == true)
    }
}
