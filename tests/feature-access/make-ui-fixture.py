"""Build an isolated UI fixture for Feature Access testing using actual app sources."""
from pathlib import Path
import shutil
import sys

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('/private/tmp/jewel-admin-feature-fixture')
out.mkdir(parents=True, exist_ok=True)

# 1. Copy app sources and xcconfig
shutil.copytree(root / 'AdminPanel', out / 'AdminPanel', dirs_exist_ok=True)
shutil.copy2(root / 'Config.xcconfig', out / 'Config.xcconfig')

# 2. Configure project.yml with UI testing bundle
s = (root / 'project.yml').read_text()
s = s.replace('bundleIdPrefix: com.jewelindia', 'bundleIdPrefix: com.jewelindia.fixture')
s = s.replace('    scheme: {}', '')
s += '''
  AdminPanelUITests:
    type: bundle.ui-testing
    platform: iOS
    deploymentTarget: "26.0"
    sources: [UITests]
    dependencies:
      - target: AdminPanel
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
schemes:
  AdminPanel:
    build:
      targets:
        AdminPanel: all
        AdminPanelUITests: [test]
    test:
      targets: [AdminPanelUITests]
'''
(out / 'project.yml').write_text(s)

# 3. Patch AdminAPI.swift to route requests through Fixture instead of Supabase network
p = out / 'AdminPanel/Sources/Core/AdminAPI.swift'
content = p.read_text()
start_idx = content.index('    private static func invoke<')
try_idx = content.index('        do {', start_idx)
void_idx = content.index('    private static func invokeVoid', try_idx)

patched_invoke = '''        let encoded = try JSONEncoder().encode(body)
        let payload = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        let response = try Fixture.response(function, payload: payload)
        return try JSONDecoder().decode(Response.self, from: JSONSerialization.data(withJSONObject: response))
    }

'''
content = content[:try_idx] + patched_invoke + content[void_idx:]
p.write_text(content)

# 4. Create RootView.swift that hosts FeatureAccessView in an isolated container
(out / 'AdminPanel/Sources/Navigation/RootView.swift').write_text('''import SwiftUI

struct RootView: View {
    @State private var colorScheme: ColorScheme = .light

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Wholesaler Review (Test)")
                            .font(.title2.bold())
                        Spacer()
                        Button(colorScheme == .light ? "Dark Mode" : "Light Mode") {
                            colorScheme = (colorScheme == .light ? .dark : .light)
                        }
                        .accessibilityIdentifier("theme-toggle")
                    }

                    // Mounted exactly as WholesalerReviewView does for wholesalers
                    FeatureAccessView(wholesalerID: Fixture.wholesalerID)
                }
                .padding()
            }
            .navigationTitle("Wholesaler Review")
        }
        .preferredColorScheme(colorScheme)
    }
}
''')

# 5. Create Fixture.swift with in-memory feature flag database
(out / 'AdminPanel/Sources/Core/Fixture.swift').write_text('''import Foundation

enum Fixture {
    static let wholesalerID = "11111111-1111-4111-8111-111111111111"

    struct FlagState {
        var key: String
        var label: String
        var description: String
        var parent_key: String?
        var default_enabled: Bool
        var enforcement_mode: String
        var override_enabled: Bool?
        var effective_enabled: Bool
        var reason: String?
        var updated_by: String?
        var updated_at: String?
        var version: Int
        var parent_locked: Bool
    }

    static var setCallCount = 0
    static var lastSetPayload: [String: Any]? = nil

    static var flags: [String: FlagState] = [
        "chamak": FlagState(
            key: "chamak",
            label: "Chamak",
            description: "Short video feed for product discovery",
            parent_key: nil,
            default_enabled: true,
            enforcement_mode: "enforce",
            override_enabled: nil,
            effective_enabled: true,
            reason: nil,
            updated_by: nil,
            updated_at: nil,
            version: 0,
            parent_locked: false
        ),
        "set_creation": FlagState(
            key: "set_creation",
            label: "Set Creation",
            description: "Create matching sets of items",
            parent_key: "chamak",
            default_enabled: true,
            enforcement_mode: "enforce",
            override_enabled: nil,
            effective_enabled: true,
            reason: nil,
            updated_by: nil,
            updated_at: nil,
            version: 0,
            parent_locked: false
        ),
        "custom_inquiries": FlagState(
            key: "custom_inquiries",
            label: "Custom Inquiries",
            description: "Receive customized RFQs from verified retailers",
            parent_key: nil,
            default_enabled: true,
            enforcement_mode: "enforce",
            override_enabled: false,
            effective_enabled: false,
            reason: "Account under review",
            updated_by: "admin-password",
            updated_at: "2026-10-18T10:00:00Z",
            version: 2,
            parent_locked: false
        ),
        "publish_to_wholesaler": FlagState(
            key: "publish_to_wholesaler",
            label: "Publish to Wholesaler",
            description: "B2B catalog sharing between wholesalers",
            parent_key: nil,
            default_enabled: false,
            enforcement_mode: "off",
            override_enabled: nil,
            effective_enabled: false,
            reason: nil,
            updated_by: nil,
            updated_at: nil,
            version: 0,
            parent_locked: false
        )
    ]

    static var auditRows: [[String: Any]] = [
        [
            "id": "e0e29b12-91f7-4be7-8a43-6df15df2d301",
            "wholesaler_user_id": wholesalerID,
            "feature_key": "custom_inquiries",
            "action": "set",
            "old_value": ["enabled": true, "version": 1],
            "new_value": ["enabled": false, "version": 2],
            "reason": "Account under review",
            "actor": "admin-password",
            "created_at": "2026-10-18T10:00:00Z"
        ]
    ]

    static var catalog: [[String: Any]] = [
        [
            "key": "chamak",
            "label": "Chamak",
            "description": "Short video feed for product discovery",
            "default_enabled": true,
            "enforcement_mode": "enforce",
            "locked_message": "Chamak has been locked for your account by Jewel India admin.",
            "updated_at": "2026-10-17T12:00:00Z"
        ],
        [
            "key": "set_creation",
            "label": "Set Creation",
            "description": "Create matching sets of items",
            "parent_key": "chamak",
            "default_enabled": true,
            "enforcement_mode": "enforce",
            "locked_message": "Set Creation has been locked for your account by Jewel India admin.",
            "updated_at": "2026-10-17T12:00:00Z"
        ],
        [
            "key": "custom_inquiries",
            "label": "Custom Inquiries",
            "description": "Receive customized RFQs from verified retailers",
            "default_enabled": true,
            "enforcement_mode": "enforce",
            "locked_message": "Custom Inquiries has been locked for your account by Jewel India admin.",
            "updated_at": "2026-10-17T12:00:00Z"
        ],
        [
            "key": "publish_to_wholesaler",
            "label": "Publish to Wholesaler",
            "description": "B2B catalog sharing between wholesalers",
            "default_enabled": false,
            "enforcement_mode": "off"
        ]
    ]

    static func response(_ function: String, payload: [String: Any]) throws -> [String: Any] {
        guard function == "admin-feature-flags" else {
            throw AdminAPIError(message: "Unknown function: \\(function)")
        }

        let action = payload["action"] as? String ?? ""

        if action == "list" {
            let chamakEffective = flags["chamak"]?.effective_enabled ?? true
            // Parent locking logic: if chamak is disabled, set_creation is parent-locked and effectively disabled
            var setCreation = flags["set_creation"]!
            if !chamakEffective {
                setCreation.parent_locked = true
                setCreation.effective_enabled = false
            } else {
                setCreation.parent_locked = false
                setCreation.effective_enabled = setCreation.override_enabled ?? setCreation.default_enabled
            }
            flags["set_creation"] = setCreation

            let orderedKeys = ["chamak", "set_creation", "custom_inquiries", "publish_to_wholesaler"]
            let items: [[String: Any]] = orderedKeys.compactMap { k in
                guard let f = flags[k] else { return nil }
                var d: [String: Any] = [
                    "key": f.key,
                    "label": f.label,
                    "description": f.description,
                    "default_enabled": f.default_enabled,
                    "enforcement_mode": f.enforcement_mode,
                    "effective_enabled": f.effective_enabled,
                    "version": f.version,
                    "parent_locked": f.parent_locked
                ]
                if let p = f.parent_key { d["parent_key"] = p }
                if let ov = f.override_enabled { d["override_enabled"] = ov }
                if let r = f.reason { d["reason"] = r }
                if let u = f.updated_by { d["updated_by"] = u }
                if let at = f.updated_at { d["updated_at"] = at }
                return d
            }
            return ["ok": true, "features": items]
        }

        if action == "set" {
            let key = payload["feature_key"] as! String
            let enabled = payload["enabled"] as! Bool
            let reason = payload["reason"] as! String
            let expectedVersion = payload["expected_version"] as? Int ?? 0

            // Simulate VERSION_CONFLICT if reason requests it
            if reason.contains("trigger-conflict") {
                throw AdminAPIError(message: "Another admin changed this. Refreshed — please try again.", code: "VERSION_CONFLICT", status: 409)
            }

            guard var flag = flags[key] else {
                throw AdminAPIError(message: "Feature not found", code: "UNKNOWN_FEATURE", status: 400)
            }

            if flag.version != expectedVersion {
                throw AdminAPIError(message: "Conflict", code: "VERSION_CONFLICT", status: 409)
            }

            setCallCount += 1
            lastSetPayload = payload

            flag.override_enabled = enabled
            flag.effective_enabled = enabled
            flag.version += 1
            flag.reason = reason
            flag.updated_by = "admin-password"
            flag.updated_at = ISO8601DateFormatter().string(from: Date())
            flags[key] = flag

            auditRows.insert([
                "id": UUID().uuidString,
                "wholesaler_user_id": wholesalerID,
                "feature_key": key,
                "action": "set",
                "old_value": ["enabled": !enabled],
                "new_value": ["enabled": enabled, "version": flag.version],
                "reason": reason,
                "actor": "admin-password",
                "created_at": flag.updated_at!
            ], at: 0)

            return ["ok": true, "version": flag.version]
        }

        if action == "reset" {
            let key = payload["feature_key"] as! String
            let reason = payload["reason"] as! String
            guard var flag = flags[key] else {
                throw AdminAPIError(message: "Feature not found", code: "UNKNOWN_FEATURE", status: 400)
            }

            flag.override_enabled = nil
            flag.effective_enabled = flag.default_enabled
            flag.version = 0
            flag.reason = nil
            flag.updated_by = nil
            flag.updated_at = nil
            flags[key] = flag

            auditRows.insert([
                "id": UUID().uuidString,
                "wholesaler_user_id": wholesalerID,
                "feature_key": key,
                "action": "reset",
                "old_value": nil,
                "new_value": nil,
                "reason": reason,
                "actor": "admin-password",
                "created_at": ISO8601DateFormatter().string(from: Date())
            ], at: 0)

            return ["ok": true, "version": 0]
        }

        if action == "audit" {
            return ["ok": true, "rows": auditRows, "count": auditRows.count, "page": 0, "pageSize": 25]
        }

        if action == "catalog_list" {
            return ["ok": true, "catalog": catalog]
        }

        if action == "catalog_set" {
            let key = payload["feature_key"] as! String
            let def = payload["default_enabled"] as? Bool
            let mode = payload["enforcement_mode"] as? String

            for i in 0..<catalog.count {
                if (catalog[i]["key"] as? String) == key {
                    if let def { catalog[i]["default_enabled"] = def }
                    if let mode { catalog[i]["enforcement_mode"] = mode }
                }
            }
            return ["ok": true]
        }

        throw AdminAPIError(message: "Unsupported fixture action: \\(action)")
    }
}
''')

# 6. Create UITests/FeatureAccessUITests.swift
(out / 'UITests').mkdir(exist_ok=True)
(out / 'UITests/FeatureAccessUITests.swift').write_text('''import XCTest

final class FeatureAccessUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func saveScreenshot(name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let targetDir = "/Users/parashrautela/Documents/jewel india /plans/feature-controls/admin-ios-screenshots"
        let fileURL = URL(fileURLWithPath: "\\(targetDir)/\\(name).png")
        try? screenshot.pngRepresentation.write(to: fileURL)
    }

    func testFeatureAccessFullWorkflow() throws {
        // --- 1. Initial State & Custom/Not Enforced Badges ---
        let cardTitle = app.staticTexts["Feature Access"]
        XCTAssertTrue(cardTitle.waitForExistence(timeout: 10), "Feature Access card must exist")

        let chamakToggle = app.switches["feature-toggle-chamak"]
        XCTAssertTrue(chamakToggle.waitForExistence(timeout: 10), "Chamak toggle must exist")
        XCTAssertEqual(chamakToggle.value as? String, "1", "Chamak should initially be ON")

        // Badges check
        XCTAssertTrue(app.staticTexts["Custom"].exists, "'Custom' badge must exist on overridden row")
        XCTAssertTrue(app.staticTexts["Not enforced yet"].exists, "'Not enforced yet' badge must exist")

        // Screenshot: 01_card_light
        saveScreenshot(name: "01_card_light")

        // --- 2. Placement & Custom Binding (C3): Toggle doesn't flip on tap ---
        chamakToggle.tap()

        // Form expands directly under Chamak row
        let chamakFormTitle = app.staticTexts["Turn Chamak off for this wholesaler?"]
        XCTAssertTrue(chamakFormTitle.waitForExistence(timeout: 5), "Inline off-form must appear directly under Chamak")
        XCTAssertTrue(app.staticTexts["Turning Chamak off also turns Set Creation off."].exists, "Chamak warning must be visible")

        // Assert toggle STILL shows 1 (ON) while inline form is open
        XCTAssertEqual(chamakToggle.value as? String, "1", "C3: Toggle must NOT change before server confirmation while form is open")

        let chamakConfirmBtn = app.buttons["feature-confirm-chamak"]
        XCTAssertFalse(chamakConfirmBtn.isEnabled, "Turn Chamak off button must be disabled until reason is entered")

        // Screenshot: 02_inline_off_form_under_chamak_light
        saveScreenshot(name: "02_inline_off_form_under_chamak_light")

        // --- 3. Cancel sends nothing and keeps toggle unchanged ---
        let chamakCancelBtn = app.buttons["feature-cancel-chamak"]
        chamakCancelBtn.tap()

        XCTAssertFalse(chamakFormTitle.exists, "Inline form must close on Cancel")
        XCTAssertEqual(chamakToggle.value as? String, "1", "C3: Toggle must remain unchanged after Cancel")

        // --- 4. Confirming Chamak off flips toggle only after server 200 OK and locks child ---
        chamakToggle.tap()
        XCTAssertTrue(chamakFormTitle.waitForExistence(timeout: 3))

        let reasonField = app.textViews["feature-reason-chamak"].exists ? app.textViews["feature-reason-chamak"] : app.textFields["feature-reason-chamak"]
        reasonField.tap()
        reasonField.typeText("Violation of quality guidelines")

        XCTAssertTrue(chamakConfirmBtn.isEnabled, "Confirm button should be enabled with valid reason")
        chamakConfirmBtn.tap()

        // Success banner
        let successNotice = app.staticTexts["feature-notice"]
        XCTAssertTrue(successNotice.waitForExistence(timeout: 5), "Success banner must appear")
        XCTAssertTrue(app.staticTexts["Chamak turned off."].exists, "Success text must confirm Chamak turned off")

        // Toggle now reflects 0 (OFF) from the reloaded server state
        XCTAssertEqual(chamakToggle.value as? String, "0", "Chamak toggle must now be OFF after reload")

        // Set Creation must now be parent-locked
        let parentLockBadge = app.staticTexts["Locked (Chamak off)"]
        XCTAssertTrue(parentLockBadge.waitForExistence(timeout: 5), "Set Creation must display 'Locked (Chamak off)' badge")
        let setCreationToggle = app.switches["feature-toggle-set_creation"]
        XCTAssertFalse(setCreationToggle.isEnabled, "Set Creation toggle must be disabled when parent is locked")

        // --- 5. Custom Row & Reset to Default ---
        let resetBtn = app.buttons["feature-reset-custom_inquiries"]
        XCTAssertTrue(resetBtn.waitForExistence(timeout: 5), "Reset to default button must be present on Custom row")

        // Screenshot: 03_custom_row_light
        saveScreenshot(name: "03_custom_row_light")

        resetBtn.tap()
        let resetConfirmTitle = app.staticTexts["Reset Custom Inquiries to default?"]
        XCTAssertTrue(resetConfirmTitle.waitForExistence(timeout: 5), "Inline reset form must expand under custom_inquiries")

        let resetReasonField = app.textViews["feature-reason-custom_inquiries"].exists ? app.textViews["feature-reason-custom_inquiries"] : app.textFields["feature-reason-custom_inquiries"]
        resetReasonField.tap()
        resetReasonField.typeText("Restoring standard permissions")

        let resetConfirmBtn = app.buttons["feature-confirm-custom_inquiries"]
        XCTAssertTrue(resetConfirmBtn.isEnabled)
        resetConfirmBtn.tap()

        XCTAssertTrue(app.staticTexts["Reset Custom Inquiries to default."].waitForExistence(timeout: 5))

        // --- 6. VERSION_CONFLICT Handling ---
        chamakToggle.tap()
        let conflictReason = app.textViews["feature-reason-chamak"].exists ? app.textViews["feature-reason-chamak"] : app.textFields["feature-reason-chamak"]
        conflictReason.tap()
        conflictReason.typeText("trigger-conflict on save")
        app.buttons["feature-confirm-chamak"].tap()

        let conflictNotice = app.staticTexts["feature-error"]
        XCTAssertTrue(conflictNotice.waitForExistence(timeout: 5), "Conflict error must be displayed")
        XCTAssertTrue(app.staticTexts["Another admin changed this. Refreshed — please try again."].exists)

        // --- 7. History View ---
        let historyBtn = app.buttons["feature-history-button"]
        historyBtn.tap()

        let historyNavTitle = app.staticTexts["Feature Flag Audit Log"]
        XCTAssertTrue(historyNavTitle.waitForExistence(timeout: 5), "History view must open")

        // Screenshot: 04_history_light
        saveScreenshot(name: "04_history_light")

        app.buttons["Done"].tap()
        XCTAssertFalse(historyNavTitle.exists, "History view must dismiss on Done")

        // --- 8. Global Defaults Screen & Inline Catalog Editor ---
        let defaultsBtn = app.buttons["feature-defaults-button"]
        defaultsBtn.tap()

        let catalogNavTitle = app.staticTexts["Global Feature Catalog"]
        XCTAssertTrue(catalogNavTitle.waitForExistence(timeout: 5), "Global catalog view must open")
        XCTAssertTrue(app.staticTexts["This affects every wholesaler. A wholesaler's switch only blocks anything when the mode is enforce."].exists)

        let editChamakCatalogBtn = app.buttons["catalog-edit-chamak"]
        editChamakCatalogBtn.tap()

        let catalogEditorTitle = app.staticTexts["Edit global default: Chamak"]
        XCTAssertTrue(catalogEditorTitle.waitForExistence(timeout: 5), "Catalog editor must open inline under Chamak")
        XCTAssertTrue(app.staticTexts["Set Creation has its own mode — change it too."].exists, "Chamak catalog note must be visible")

        let catalogSaveBtn = app.buttons["catalog-save-chamak"]
        XCTAssertFalse(catalogSaveBtn.isEnabled, "Global save must be disabled before reason and typed confirmation")

        let catalogReasonField = app.textViews["catalog-reason-chamak"].exists ? app.textViews["catalog-reason-chamak"] : app.textFields["catalog-reason-chamak"]
        catalogReasonField.tap()
        catalogReasonField.typeText("Testing global defaults configuration")

        XCTAssertFalse(catalogSaveBtn.isEnabled, "Save must still be disabled without typed confirmation key")

        let catalogConfirmField = app.textFields["catalog-confirm-key-chamak"]
        catalogConfirmField.tap()
        catalogConfirmField.typeText("chamak")

        XCTAssertTrue(catalogSaveBtn.isEnabled, "Save must be enabled when key matches 'chamak' exactly")

        // Screenshot: 05_global_defaults_with_inline_editor_light
        saveScreenshot(name: "05_global_defaults_with_inline_editor_light")

        app.buttons["catalog-cancel-chamak"].tap()
        app.buttons["Done"].tap()

        // --- 9. Dark Mode Verification & Dark Screenshots ---
        let themeToggle = app.buttons["theme-toggle"]
        themeToggle.tap()

        // Capture Dark Mode Screenshots
        saveScreenshot(name: "06_card_dark")

        chamakToggle.tap()
        _ = chamakFormTitle.waitForExistence(timeout: 3)
        saveScreenshot(name: "07_inline_off_form_under_chamak_dark")
        app.buttons["feature-cancel-chamak"].tap()

        historyBtn.tap()
        _ = historyNavTitle.waitForExistence(timeout: 3)
        saveScreenshot(name: "08_history_dark")
        app.buttons["Done"].tap()

        defaultsBtn.tap()
        _ = catalogNavTitle.waitForExistence(timeout: 3)
        app.buttons["catalog-edit-chamak"].tap()
        _ = catalogEditorTitle.waitForExistence(timeout: 3)
        saveScreenshot(name: "09_global_defaults_with_inline_editor_dark")
        app.buttons["catalog-cancel-chamak"].tap()
        app.buttons["Done"].tap()
    }
}
''')

print('UI fixture generated at', out)
