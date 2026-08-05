import Foundation
import Testing
@testable import PalmierPro

@Suite("Community skill auto-install")
struct CommunitySkillAutoInstallTests {
    struct Case: Sendable {
        let localSHA: String?
        let installedSHA: String?
        let catalogSHA: String
        let isSuppressed: Bool
        let expected: Bool
    }

    @Test(arguments: [
        Case(
            localSHA: nil,
            installedSHA: nil,
            catalogSHA: "new",
            isSuppressed: false,
            expected: true
        ),
        Case(
            localSHA: nil,
            installedSHA: nil,
            catalogSHA: "new",
            isSuppressed: true,
            expected: false
        ),
        Case(
            localSHA: "local",
            installedSHA: nil,
            catalogSHA: "catalog",
            isSuppressed: false,
            expected: false
        ),
        Case(
            localSHA: "old",
            installedSHA: "old",
            catalogSHA: "new",
            isSuppressed: false,
            expected: true
        ),
        Case(
            localSHA: "current",
            installedSHA: "current",
            catalogSHA: "current",
            isSuppressed: false,
            expected: false
        ),
        Case(
            localSHA: "modified",
            installedSHA: "old",
            catalogSHA: "new",
            isSuppressed: false,
            expected: false
        ),
        Case(
            localSHA: nil,
            installedSHA: "old",
            catalogSHA: "new",
            isSuppressed: false,
            expected: false
        ),
    ]) func installsOnlyNewOrUntouchedSkills(testCase: Case) {
        #expect(
            SkillStore.shouldAutomaticallyInstall(
                localSHA: testCase.localSHA,
                installedSHA: testCase.installedSHA,
                catalogSHA: testCase.catalogSHA,
                isSuppressed: testCase.isSuppressed
            ) == testCase.expected
        )
    }

    @Test func malformedSuppressionStateFailsClosed() throws {
        let valid = try JSONEncoder().encode(["captions", "grading"])

        #expect(SkillStore.decodeSuppressed(valid) == ["captions", "grading"])
        #expect(SkillStore.decodeSuppressed(Data("not json".utf8)) == nil)
    }
}
