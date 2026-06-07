import Foundation
import XCTest
@testable import BilinWorkspaceKit

final class BilinResearchAPIClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testListResearchPlansBuildsFilteredQueryAndDecodesResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/libraries/library-1/research-plans")

            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(queryItems["article_revision_id"], "rev-1")
            XCTAssertEqual(queryItems["status"], "active")
            XCTAssertEqual(queryItems["kind"], "paper_reading")

            let body = """
            [
              {
                "id": "plan-1",
                "kind": "paper_reading",
                "status": "active",
                "title": "Draft from candidate papers",
                "article_revision_id": "rev-1",
                "payload_hash": "hash-plan",
                "candidate_papers": [
                  {
                    "id": "2401.00001"
                  }
                ],
                "reading_outline": {
                  "title": "Draft from candidate papers",
                  "paperMasteryOutlines": [
                    {
                      "paper_id": "2401.00001",
                      "paper_title": "A sample paper",
                      "followUp": ["test on larger baselines"]
                    }
                  ]
                },
                "payload": {},
                "preview": null,
                "result": null,
                "error": null,
                "created_at": "2027-01-15T08:00:00Z",
                "updated_at": "2027-01-15T08:00:00Z"
              }
            ]
            """
            return Self.makeResponse(body)
        }

        let plans = try await makeClient().listResearchPlans(
            libraryId: "library-1",
            articleRevisionId: "rev-1",
            status: .active,
            kind: .paperReading
        )

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].readingOutline?.paperMasteryOutlines.first?.paperId, "2401.00001")
        XCTAssertEqual(plans[0].readingOutline?.paperMasteryOutlines.first?.followUp, ["test on larger baselines"])
    }

    func testHealthChecksBackendEndpointAndDecodesStatus() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/health")
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer token")

            return Self.makeResponse("""
            {
              "status": "ok",
              "app": "Ilios",
              "version": "0.3.6"
            }
            """)
        }

        let health = try await makeClient().health()

        XCTAssertEqual(health.status, "ok")
        XCTAssertEqual(health.app, "Ilios")
        XCTAssertEqual(health.version, "0.3.6")
    }


    func testGenerateResearchPlanActionPlanPostsExpectedPayload() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/libraries/library-1/research-plans/generate")
            XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")

            let data = try XCTUnwrap(Self.requestBodyData(from: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(json["title"] as? String, "Draft from candidate papers")
            XCTAssertEqual(json["kind"] as? String, "paper_reading")
            XCTAssertEqual(json["article_revision_id"] as? String, "rev-1")
            XCTAssertEqual(json["skill_slug"] as? String, "paper-outline")
            XCTAssertEqual(json["idempotency_key"] as? String, "plan-key")

            let candidatePapers = try XCTUnwrap(json["candidate_papers"] as? [[String: Any]])
            XCTAssertEqual(candidatePapers.first?["id"] as? String, "2401.00001")
            XCTAssertEqual(candidatePapers.first?["follow_up"] as? [String], ["test on larger baselines"])

            let payload = try XCTUnwrap(json["payload"] as? [String: Any])
            XCTAssertEqual(payload["seed"] as? String, "2401.00001")

            let body = """
            {
              "id": "action-1",
              "kind": "generate_research_outline",
              "status": "pending",
              "title": "Generate reading outline: Draft from candidate papers",
              "description": "Generate an auditable research plan outline from candidate papers.",
              "payload_hash": "hash-action",
              "idempotency_key": "plan-key",
              "required_permissions": [],
              "payload": {
                "title": "Draft from candidate papers",
                "candidate_papers": [
                  {
                    "id": "2401.00001"
                  }
                ]
              },
              "preview": {
                "title": "Draft from candidate papers",
                "kind": "paper_reading",
                "reading_outline": {
                  "title": "Preview outline",
                  "questions": ["What should be checked before implementation?"]
                }
              },
              "result": {
                "reading_outline": {
                  "title": "Generated outline",
                  "summary": "Understand the proof before the benchmark.",
                  "paperMasteryOutlines": [
                    {
                      "paper_id": "2401.00001",
                      "paper_title": "A sample paper",
                      "claim": ["The method converges."]
                    }
                  ]
                }
              },
              "steps": [],
              "created_at": "2027-01-15T08:00:00Z",
              "updated_at": "2027-01-15T08:00:00Z",
              "approved_at": null,
              "finished_at": null,
              "error": null
            }
            """
            return Self.makeResponse(body, statusCode: 201)
        }

        let actionPlan = try await makeClient().generateResearchPlanActionPlan(
            libraryId: "library-1",
            request: ResearchPlanGenerationRequest(
                title: "Draft from candidate papers",
                kind: .paperReading,
                topic: "adaptive optimization",
                articleRevisionId: "rev-1",
                skillSlug: "paper-outline",
                candidatePapers: [
                    [
                        "id": .string("2401.00001"),
                        "follow_up": .array([.string("test on larger baselines")])
                    ]
                ],
                idempotencyKey: "plan-key",
                payload: ["seed": .string("2401.00001")]
            )
        )

        XCTAssertEqual(actionPlan.kind, .generateResearchOutline)
        XCTAssertEqual(actionPlan.status, .pendingApproval)
        XCTAssertEqual(actionPlan.title, "Generate reading outline: Draft from candidate papers")
        XCTAssertEqual(actionPlan.idempotencyKey, "plan-key")
        XCTAssertTrue(actionPlan.payload["candidate_papers"]?.contains("2401.00001") ?? false)
        XCTAssertTrue(actionPlan.preview?["reading_outline"]?.contains("Preview outline") ?? false)
        let resultOutline = try XCTUnwrap(actionPlan.result?["reading_outline"])
        let resultJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(resultOutline.utf8)) as? [String: Any])
        XCTAssertEqual(resultJSON["title"] as? String, "Generated outline")
        XCTAssertEqual(resultJSON["summary"] as? String, "Understand the proof before the benchmark.")
    }

    func testAgentActionPlanTransitionsPostExpectedEndpointsAndBodies() async throws {
        let cases: [TransitionCase] = [
            TransitionCase(
                transition: "approve",
                returnedStatus: "approved",
                assertBody: { json in
                    XCTAssertEqual(json["expected_payload_hash"] as? String, "hash-action")
                    XCTAssertEqual((json["payload"] as? [String: Any])?["approved_by"] as? String, "macos")
                },
                perform: {
                    try await $0.approveAgentActionPlan(
                        libraryId: "library-1",
                        actionPlanId: "action-1",
                        expectedPayloadHash: "hash-action",
                        payload: ["approved_by": "macos"]
                    )
                }
            ),
            TransitionCase(
                transition: "reject",
                returnedStatus: "rejected",
                assertBody: { json in
                    XCTAssertEqual((json["payload"] as? [String: Any])?["rejected_by"] as? String, "macos")
                },
                perform: {
                    try await $0.rejectAgentActionPlan(
                        libraryId: "library-1",
                        actionPlanId: "action-1",
                        payload: ["rejected_by": "macos"]
                    )
                }
            ),
            TransitionCase(
                transition: "start",
                returnedStatus: "running",
                assertBody: { json in
                    XCTAssertEqual((json["payload"] as? [String: Any])?["executor"] as? String, "macos")
                },
                perform: {
                    try await $0.startAgentActionPlan(
                        libraryId: "library-1",
                        actionPlanId: "action-1",
                        payload: ["executor": "macos"]
                    )
                }
            ),
            TransitionCase(
                transition: "succeed",
                returnedStatus: "succeeded",
                assertBody: { json in
                    XCTAssertEqual((json["result"] as? [String: Any])?["target_path"] as? String, "/tmp/target.md")
                },
                perform: {
                    try await $0.succeedAgentActionPlan(
                        libraryId: "library-1",
                        actionPlanId: "action-1",
                        result: ["target_path": "/tmp/target.md"]
                    )
                }
            ),
            TransitionCase(
                transition: "fail",
                returnedStatus: "failed",
                assertBody: { json in
                    XCTAssertEqual((json["error"] as? [String: Any])?["code"] as? String, "local_patch_failed")
                },
                perform: {
                    try await $0.failAgentActionPlan(
                        libraryId: "library-1",
                        actionPlanId: "action-1",
                        error: ["code": "local_patch_failed"]
                    )
                }
            )
        ]

        for testCase in cases {
            MockURLProtocol.requestHandler = { request in
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(
                    request.url?.path,
                    "/libraries/library-1/agent-action-plans/action-1/\(testCase.transition)"
                )
                XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer token")
                let data = try XCTUnwrap(Self.requestBodyData(from: request))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                testCase.assertBody(json)
                return Self.makeResponse(Self.actionPlanResponse(status: testCase.returnedStatus))
            }

            let actionPlan = try await testCase.perform(makeClient())
            XCTAssertEqual(actionPlan.id, "action-1")
            XCTAssertEqual(actionPlan.status.backendValueForTest, testCase.returnedStatus)
            if testCase.returnedStatus == "failed" {
                XCTAssertEqual(actionPlan.error?["code"], "file_changed_since_preview")
                XCTAssertEqual(actionPlan.error?["expected_base_file_hash"], "old")
                XCTAssertEqual(actionPlan.errorMessage, "Target file changed since preview.")
            }
        }
    }

    private func makeClient() -> BilinResearchAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return BilinResearchAPIClient(
            baseURL: URL(string: "http://127.0.0.1:8000")!,
            apiToken: "token",
            session: session
        )
    }

    private static func makeResponse(_ body: String, statusCode: Int = 200) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:8000/mock")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    private static func requestBodyData(from request: URLRequest) -> Data? {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while true {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else if bytesRead == 0 {
                return data
            } else {
                return nil
            }
        }
    }

    private static func actionPlanResponse(status: String) -> String {
        let errorPayload = status == "failed"
            ? """
              {
                "code": "file_changed_since_preview",
                "message": "Target file changed since preview.",
                "expected_base_file_hash": "old",
                "observed_file_hash": "new"
              }
              """
            : "null"
        return """
        {
          "id": "action-1",
          "kind": "write_obsidian",
          "status": "\(status)",
          "title": "Write Obsidian note patch",
          "description": "Preview Markdown note patch.",
          "payload_hash": "hash-action",
          "idempotency_key": "action-key",
          "required_permissions": ["write_obsidian"],
          "payload": {
            "target_note": "Papers/Seed.md"
          },
          "preview": {
            "patch": "> Patch"
          },
          "result": null,
          "steps": [],
          "created_at": "2027-01-15T08:00:00Z",
          "updated_at": "2027-01-15T08:00:00Z",
          "approved_at": null,
          "finished_at": null,
          "error": \(errorPayload)
        }
        """
    }
}

private struct TransitionCase {
    var transition: String
    var returnedStatus: String
    var assertBody: ([String: Any]) -> Void
    var perform: (BilinResearchAPIClient) async throws -> AgentActionPlan
}

private extension AgentActionStatus {
    var backendValueForTest: String {
        switch self {
        case .draft, .pendingApproval:
            return "pending"
        case .approved:
            return "approved"
        case .queued:
            return "queued"
        case .rejected:
            return "rejected"
        case .cancelled:
            return "cancelled"
        case .running:
            return "running"
        case .succeeded:
            return "succeeded"
        case .failed:
            return "failed"
        }
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
