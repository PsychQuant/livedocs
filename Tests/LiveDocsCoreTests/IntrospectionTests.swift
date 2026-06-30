import XCTest
@testable import LiveDocsCore

final class IntrospectionTests: XCTestCase {

    // MARK: OpenAPI

    func testParseOpenAPI() throws {
        let json = """
        {"openapi":"3.1.0","info":{"title":"Pet Store","version":"2.4.0"},
         "paths":{
           "/pets":{"get":{"summary":"List pets","operationId":"listPets"},
                    "post":{"operationId":"createPet"},
                    "parameters":[{"name":"x"}]},
           "/pets/{id}":{"get":{"summary":"Get pet"}}}}
        """.data(using: .utf8)!
        let s = try parseOpenAPI(json)
        XCTAssertEqual(s.title, "Pet Store")
        XCTAssertEqual(s.apiVersion, "2.4.0")
        XCTAssertEqual(s.specVersion, "3.1.0")
        // 3 real operations; the `parameters` sibling is NOT mistaken for a verb.
        XCTAssertEqual(s.operations.count, 3)
        XCTAssertEqual(s.operations.first, OpenAPIOperation(method: "GET", path: "/pets", summary: "List pets", operationId: "listPets"))
    }

    func testParseSwagger2() throws {
        let json = #"{"swagger":"2.0","info":{"version":"1.0"},"paths":{"/a":{"get":{}}}}"#.data(using: .utf8)!
        let s = try parseOpenAPI(json)
        XCTAssertEqual(s.specVersion, "2.0")
        XCTAssertEqual(s.operations.count, 1)
    }

    func testNonOpenAPIRejected() {
        // A plain JSON object without openapi/swagger marker is not a spec.
        XCTAssertThrowsError(try parseOpenAPI(Data(#"{"hello":"world"}"#.utf8)))
        XCTAssertThrowsError(try parseOpenAPI(Data("<html>".utf8)))
    }

    func testOpenAPICandidatesCoverFrameworks() {
        let c = openAPICandidates(for: "https://api.example.com")
        XCTAssertTrue(c.contains("https://api.example.com/openapi.json"))
        XCTAssertTrue(c.contains("https://api.example.com/v3/api-docs"))   // Spring
        XCTAssertTrue(c.contains("https://api.example.com/swagger.json"))
    }

    // MARK: GraphQL

    func testParseGraphQLIntrospection() throws {
        let json = """
        {"data":{"__schema":{
          "queryType":{"name":"Query"},
          "mutationType":{"name":"Mutation"},
          "subscriptionType":null,
          "types":[{"name":"Query","kind":"OBJECT"},{"name":"User","kind":"OBJECT"},
                   {"name":"String","kind":"SCALAR"},{"name":"__Type","kind":"OBJECT"}]}}}
        """.data(using: .utf8)!
        let s = try parseGraphQLIntrospection(json)
        XCTAssertEqual(s.queryType, "Query")
        XCTAssertEqual(s.mutationType, "Mutation")
        XCTAssertNil(s.subscriptionType)
        XCTAssertEqual(s.typeCount, 4)
        // __Type and String filtered; Query/User remain.
        XCTAssertEqual(s.sampleTypes, ["Query", "User"])
    }

    func testNonGraphQLRejected() {
        XCTAssertThrowsError(try parseGraphQLIntrospection(Data(#"{"errors":[]}"#.utf8)))
    }
}
