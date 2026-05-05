import Foundation
import XCTest
@testable import XcodeProj

final class XCBuildConfigurationTests: XCTestCase {
    func test_initFails_ifNameIsMissing() {
        var dictionary = testDictionary()
        dictionary.removeValue(forKey: "name")
        let data = try! JSONSerialization.data(withJSONObject: dictionary, options: [])
        let decoder = XcodeprojJSONDecoder()
        do {
            _ = try decoder.decode(XCBuildConfiguration.self, from: data)
            XCTAssertTrue(false, "Expected to throw an error but it didn't")
        } catch {}
    }

    func test_isa_hasTheCorrectValue() {
        XCTAssertEqual(XCBuildConfiguration.isa, "XCBuildConfiguration")
    }

    func test_append_when_theSettingDoesntExist() {
        // Given
        let subject = XCBuildConfiguration(name: "Debug",
                                           baseConfiguration: nil,
                                           buildSettings: [:])

        // When
        subject.append(setting: "PRODUCT_NAME", value: "$(TARGET_NAME:c99extidentifier)")

        // Then
        XCTAssertEqual(subject.buildSettings["PRODUCT_NAME"], "$(inherited) $(TARGET_NAME:c99extidentifier)")
    }

    func test_append_when_theSettingExists() {
        // Given
        let subject = XCBuildConfiguration(name: "Debug",
                                           baseConfiguration: nil,
                                           buildSettings: ["OTHER_LDFLAGS": "flag1"])

        // When
        subject.append(setting: "OTHER_LDFLAGS", value: "flag2")

        // Then
        XCTAssertEqual(subject.buildSettings["OTHER_LDFLAGS"], "flag1 flag2")
    }

    func test_append_when_duplicateSettingExists() {
        // Given
        let subject = XCBuildConfiguration(name: "Debug",
                                           baseConfiguration: nil,
                                           buildSettings: ["OTHER_LDFLAGS": "flag1"])

        // When
        subject.append(setting: "OTHER_LDFLAGS", value: "flag1")

        // Then
        XCTAssertEqual(subject.buildSettings["OTHER_LDFLAGS"], "flag1")
    }

    func test_append_removesDuplicates_when_theSettingIsAnArray() {
        // Given
        let subject = XCBuildConfiguration(name: "Debug",
                                           baseConfiguration: nil,
                                           buildSettings: [
                                               "OTHER_LDFLAGS": ["flag1", "flag2"],
                                           ])

        // When
        subject.append(setting: "OTHER_LDFLAGS", value: "flag1")

        // Then
        XCTAssertEqual(subject.buildSettings["OTHER_LDFLAGS"], ["flag1", "flag2"])
    }

    func test_append_when_theSettingExistsAsAnArray() {
        // Given
        let subject = XCBuildConfiguration(name: "Debug",
                                           baseConfiguration: nil,
                                           buildSettings: ["OTHER_LDFLAGS": ["flag1", "flag2"]])

        // When
        subject.append(setting: "OTHER_LDFLAGS", value: "flag3")

        // Then
        XCTAssertEqual(subject.buildSettings["OTHER_LDFLAGS"], ["flag1", "flag2", "flag3"])
    }

    func test_configuration_files_in_synchronized_group() {
        let synchronizedGroup = PBXFileSystemSynchronizedRootGroup.fixture(sourceTree: .group,
                                                                           path: "Xcode16BuildConfigurations",
                                                                           explicitFileTypes: [:],
                                                                           exceptions: [],
                                                                           explicitFolders: [])
        let subject = XCBuildConfiguration(name: "Debug",
                                           baseConfigurationAnchor: synchronizedGroup,
                                           baseConfigurationRelativePath: "Configs/DevConfig.xcconfig",
                                           buildSettings: [:])
        XCTAssertNil(subject.baseConfigurationReference)
        XCTAssertNotNil(subject.baseConfigurationReferenceAnchor)
        XCTAssertNotNil(subject.baseConfigurationReferenceRelativePath)
    }

    func test_baseConfiguration_setter_clears_when_assigned_nil() {
        let fileReference = PBXFileReference(sourceTree: .group, name: "Foo.xcconfig")
        let subject = XCBuildConfiguration(name: "Debug",
                                           baseConfiguration: fileReference,
                                           buildSettings: [:])
        XCTAssertNotNil(subject.baseConfigurationReference)

        subject.baseConfiguration = nil

        XCTAssertNil(subject.baseConfigurationReference)
    }

    func test_baseConfigurationAnchor_setter_clears_when_assigned_nil() {
        let synchronizedGroup = PBXFileSystemSynchronizedRootGroup.fixture(sourceTree: .group, path: "config")
        let subject = XCBuildConfiguration(name: "Debug",
                                           baseConfigurationAnchor: synchronizedGroup,
                                           baseConfigurationRelativePath: "Foo.xcconfig",
                                           buildSettings: [:])
        XCTAssertNotNil(subject.baseConfigurationReferenceAnchor)

        subject.baseConfigurationAnchor = nil

        XCTAssertNil(subject.baseConfigurationReferenceAnchor)
    }

    func test_isEqual_distinguishes_synchronized_anchor_fields() {
        let groupA = PBXFileSystemSynchronizedRootGroup.fixture(sourceTree: .group, path: "config")
        let groupB = PBXFileSystemSynchronizedRootGroup.fixture(sourceTree: .group, path: "other-config")
        let baseline = XCBuildConfiguration(name: "Debug",
                                            baseConfigurationAnchor: groupA,
                                            baseConfigurationRelativePath: "Foo.xcconfig",
                                            buildSettings: [:])
        let differentAnchor = XCBuildConfiguration(name: "Debug",
                                                   baseConfigurationAnchor: groupB,
                                                   baseConfigurationRelativePath: "Foo.xcconfig",
                                                   buildSettings: [:])
        let differentRelativePath = XCBuildConfiguration(name: "Debug",
                                                         baseConfigurationAnchor: groupA,
                                                         baseConfigurationRelativePath: "Bar.xcconfig",
                                                         buildSettings: [:])

        XCTAssertFalse(baseline.isEqual(to: differentAnchor))
        XCTAssertFalse(baseline.isEqual(to: differentRelativePath))
    }

    func test_synchronizedAnchor_emits_groupName_as_comment_when_name_and_path_both_set() throws {
        // Synchronized root groups can carry both a name and a path
        // (e.g. wcios's `config` group has name = "config", path = "../config").
        // Xcode emits the group's name as the anchor comment;
        // PBXFileElement.fileName() returns name ?? path,
        // matching that behavior for sibling baseConfigurationReference comments.
        let synchronizedGroup = PBXFileSystemSynchronizedRootGroup.fixture(sourceTree: .group,
                                                                           path: "../config",
                                                                           name: "config",
                                                                           explicitFileTypes: [:],
                                                                           exceptions: [],
                                                                           explicitFolders: [])
        let subject = XCBuildConfiguration(name: "Debug",
                                           baseConfigurationAnchor: synchronizedGroup,
                                           baseConfigurationRelativePath: "WooCommerce.debug.xcconfig",
                                           buildSettings: [:])

        let proj = PBXProj()
        let plist = try subject.plistKeyAndValue(proj: proj, reference: "ref")

        guard case let .dictionary(dictionary) = plist.value,
              case let .string(anchor) = dictionary["baseConfigurationReferenceAnchor"] else {
            XCTFail("Expected baseConfigurationReferenceAnchor entry in encoded plist")
            return
        }
        XCTAssertEqual(anchor.comment, "config")
    }

    private func testDictionary() -> [String: Any] {
        [
            "baseConfigurationReference": "baseConfigurationReference",
            "buildSettings": [:],
            "name": "name",
            "reference": "reference",
        ]
    }
}
