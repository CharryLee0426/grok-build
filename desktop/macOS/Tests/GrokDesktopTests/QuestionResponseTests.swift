import XCTest
@testable import GrokDesktop

final class QuestionResponseTests: XCTestCase {
    func testSelectedAnswersArePreservedWithExplanatoryNotes() {
        let request = QuestionRequest(requestID: 1, questions: [AgentQuestion(question: "Which targets?", options: ["macOS", "Linux"], multiSelect: true)])
        let result = request.response(answers: ["Which targets?": ["Linux", "macOS"]], notes: ["Which targets?": "Start with macOS."])
        XCTAssertEqual((result["answers"] as? [String: [String]])?["Which targets?"], ["macOS", "Linux"])
        XCTAssertEqual((result["annotations"] as? [String: [String: String]])?["Which targets?"]?["notes"], "Start with macOS.")
    }

    func testFreeformAnswersUseHarnessOtherConvention() {
        let request = QuestionRequest(requestID: 1, questions: [AgentQuestion(question: "Which target?", options: ["macOS"], multiSelect: false)])
        let result = request.response(answers: [:], notes: ["Which target?": "An embedded device"])
        XCTAssertEqual((result["answers"] as? [String: [String]])?["Which target?"], ["Other"])
        XCTAssertEqual((result["annotations"] as? [String: [String: String]])?["Which target?"]?["notes"], "An embedded device")
    }
}
