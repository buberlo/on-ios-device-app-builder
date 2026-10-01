import XCTest

final class PhoneBuilderUITests: XCTestCase {
    @MainActor
    func testTabsAndMacSetup() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 5))

        app.buttons["Setup"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Setup"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Connect"].waitForExistence(timeout: 2))
        app.buttons["Connect"].tap()

        XCTAssertTrue(app.staticTexts["Xcode 26"].waitForExistence(timeout: 2))
        let installTarget = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Demo iPhone"))
            .firstMatch
        XCTAssertTrue(installTarget.waitForExistence(timeout: 2))

        app.buttons["Activity"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCreateChatAndBuildFlow() {
        let app = launchApp()
        connectToTestMac(in: app)
        let createProject = app.buttons["Create project"]
        XCTAssertTrue(createProject.waitForExistence(timeout: 5))
        createProject.tap()

        let nameField = app.textFields["project.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.typeText("Focus Timer")
        app.buttons["project.create"].tap()

        let project = app.staticTexts["Focus Timer"]
        XCTAssertTrue(project.waitForExistence(timeout: 2))
        project.tap()

        let composer = app.descendants(matching: .any)["chat.input"]
        XCTAssertTrue(composer.waitForExistence(timeout: 2))
        composer.tap()
        composer.typeText("Add a countdown ring")
        app.buttons["chat.send"].tap()

        let userMessage = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Add a countdown ring"))
            .firstMatch
        XCTAssertTrue(userMessage.waitForExistence(timeout: 2))

        app.buttons["project.build"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["project.run-log"].waitForExistence(timeout: 3))
        app.buttons["Activity"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Build succeeded"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Building"].exists)
    }

    @MainActor
    func testDisconnectedCreationShowsErrorAndKeepsDraft() {
        let app = launchApp()
        app.buttons["Create project"].tap()

        let nameField = app.textFields["project.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.typeText("Offline App")
        app.buttons["project.create"].tap()

        XCTAssertTrue(app.alerts["Connect your Mac first"].waitForExistence(timeout: 3))
        app.alerts["Connect your Mac first"].buttons["OK"].tap()
        XCTAssertTrue(nameField.exists)
        XCTAssertEqual(nameField.value as? String, "Offline App")
    }

    @MainActor
    func testDeleteProjectWithConfirmation() {
        let app = launchApp()
        connectToTestMac(in: app)
        app.buttons["Create project"].tap()
        app.textFields["project.name"].typeText("Delete Me")
        app.buttons["project.create"].tap()

        let project = app.staticTexts["Delete Me"]
        XCTAssertTrue(project.waitForExistence(timeout: 3))
        project.swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.alerts["Delete Delete Me?"].waitForExistence(timeout: 3))
        app.alerts["Delete Delete Me?"].buttons["Delete"].tap()

        XCTAssertTrue(app.staticTexts["No projects yet"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testChooseIPadAndInstall() {
        let app = launchApp()
        app.buttons["Setup"].firstMatch.tap()
        XCTAssertTrue(app.buttons["setup.connect"].waitForExistence(timeout: 3))
        app.buttons["setup.connect"].tap()

        let iPad = app.buttons["setup.device.demo-ipad"]
        let iPhone = app.buttons["setup.device.demo-iphone"]
        XCTAssertTrue(iPad.waitForExistence(timeout: 3))
        XCTAssertTrue(iPad.isEnabled)
        XCTAssertTrue(iPhone.waitForExistence(timeout: 3))
        XCTAssertFalse(iPhone.isEnabled)
        iPad.tap()

        app.buttons["Projects"].firstMatch.tap()
        app.buttons["Create project"].tap()
        app.textFields["project.name"].typeText("Device Picker")
        app.buttons["project.create"].tap()
        app.staticTexts["Device Picker"].tap()

        app.buttons["project.install"].tap()
        let installOnIPad = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Demo iPad"))
            .firstMatch
        XCTAssertTrue(installOnIPad.waitForExistence(timeout: 3))
        installOnIPad.tap()

        app.buttons["Activity"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["App installed"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["The latest build is now on Demo iPad"].exists)
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }

    @MainActor
    private func connectToTestMac(in app: XCUIApplication) {
        app.buttons["Setup"].firstMatch.tap()
        XCTAssertTrue(app.buttons["setup.connect"].waitForExistence(timeout: 3))
        app.buttons["setup.connect"].tap()
        app.buttons["Projects"].firstMatch.tap()
    }
}
