"""Build an isolated UI fixture using actual app sources; no production auth bypass."""
from pathlib import Path
import shutil, sys
root=Path(__file__).resolve().parents[2]
out=Path(sys.argv[1]); out.mkdir(parents=True,exist_ok=True)
shutil.copytree(root/'AdminPanel',out/'AdminPanel',dirs_exist_ok=True)
shutil.copy2(root/'Config.xcconfig',out/'Config.xcconfig')
s=(root/'project.yml').read_text().replace('bundleIdPrefix: com.jewelindia','bundleIdPrefix: com.jewelindia.fixture')
s=s.replace('    scheme: {}', '')
s+='''
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
(out/'project.yml').write_text(s)
p=out/'AdminPanel/Sources/Core/AdminAPI.swift';s=p.read_text()
a=s.index('        do {',s.index('    private static func invoke<'));b=s.index('    private static func invokeVoid',a)
s=s[:a]+'''        let encoded = try JSONEncoder().encode(body)
        let payload = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        let response = try Fixture.response(function, payload: payload)
        return try JSONDecoder().decode(Response.self, from: JSONSerialization.data(withJSONObject: response))
    }

'''+s[b:];p.write_text(s)
(out/'AdminPanel/Sources/Navigation/RootView.swift').write_text('''import SwiftUI
struct RootView: View {
    @State private var entity: ReviewEntity = .wholesaler
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Business type", selection: $entity) {
                        Text("Wholesaler").tag(ReviewEntity.wholesaler)
                        Text("Retailer").tag(ReviewEntity.retailer)
                    }.pickerStyle(.segmented)
                    Text(entity == .wholesaler ? "Sample wholesale business" : "Sample retail store").font(.title2)
                    BusinessCreditsAndReferrals(entity: entity, submission: Fixture.submission(entity))
                }.padding()
            }.navigationTitle("Credits & referrals")
        }.preferredColorScheme(.light)
    }
}
''')
(out/'AdminPanel/Sources/Core/Fixture.swift').write_text('''import Foundation
@MainActor enum Fixture {
    static let ws = "11111111-1111-4111-8111-111111111111"
    static let ret = "22222222-2222-4222-8222-222222222222"
    static var versions = [ws:0,ret:0]
    static var amounts = [ws:2000,ret:2000]
    static var keys = Set<String>()
    static func submission(_ entity: ReviewEntity) -> Submission {
        let json: [String: Any] = ["id": entity == .wholesaler ? ws : ret,"full_name":"Sample Owner","business_name":"Sample Business","verification_status":"verified","inviter_business_name":"Sample Wholesale Business"]
        return try! JSONDecoder().decode(Submission.self, from: JSONSerialization.data(withJSONObject: json))
    }
    static func response(_ function: String, payload: [String: Any]) throws -> [String: Any] {
        let now = Date(), formatter = ISO8601DateFormatter()
        if function == "admin-credit-allowances" {
            let id = payload["wholesaler_id"] as! String
            let role = payload["business_type"] as! String
            guard (role == "wholesaler" && id == ws) || (role == "retailer" && id == ret) else { throw AdminAPIError(message:"Wrong business target") }
            if payload["action"] as? String == "list" {
                return ["ok":true,"items":[["wholesaler_id":id,"verification_status":"verified","daily_allowance":amounts[id]!,"is_custom":amounts[id] != 2000,"policy_version":versions[id]!,"current_allowance":2000,"next_refill_at":formatter.string(from:now.addingTimeInterval(82800)),"recurring_available":1700,"gift_available":1000,"paid_available":68,"available":2768]],"server_now":formatter.string(from:now),"program_active":true,"default_allowance":2000]
            }
            guard payload["expected_version"] as? Int == versions[id], let key = payload["request_key"] as? String, UUID(uuidString:key) != nil, !(payload["reason"] as? String ?? "").isEmpty else { throw AdminAPIError(message:"Invalid version or replay key") }
            if keys.contains(key) { throw AdminAPIError(message:"Repeated fixture mutation") }
            keys.insert(key); versions[id]! += 1
            amounts[id] = payload["action"] as? String == "reset_default" ? 2000 : payload["daily_allowance"] as? Int
            return ["ok":true,"next_allowance":amounts[id]!,"program_active":true,"effective_at":formatter.string(from:now.addingTimeInterval(82800)),"replayed":false]
        }
        if function == "admin-referrals" {
            if payload["action"] as? String == "events" { return ["events":[]] }
            return ["links":[["id":ws,"code":"SAMPLE","wholesaler_id":ws,"retailer_id":ret,"inviter_name":"Sample Wholesale Business","retailer_name":"Sample Retail Store","retailer_status":"pending","status":"pending","policy_version":1,"gift_credits":1000,"extra_credits":0,"funding_state":"reserved","refunded_credits":0,"created_at":formatter.string(from:now)]],"count":1,"page":0]
        }
        throw AdminAPIError(message:"Unsupported fixture request")
    }
}
'''.replace('@MainActor enum Fixture','enum Fixture'))
(out/'UITests').mkdir(exist_ok=True)
(out/'UITests/CreditsTests.swift').write_text('''import XCTest
final class CreditsTests: XCTestCase {
    func testBothBusinessRoles() throws {
        let app = XCUIApplication(); app.launch()
        for role in ["Wholesaler", "Retailer"] {
            app.buttons[role].tap()
            let change = app.buttons["Change credits"]
            XCTAssertTrue(change.waitForExistence(timeout:10)); change.tap()
            let amount = app.textFields["credit-amount"]
            amount.tap()
            amount.press(forDuration:1.2)
            if app.menuItems["Select All"].waitForExistence(timeout:2) { app.menuItems["Select All"].tap() }
            else { amount.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:4)) }
            amount.typeText("3500")
            let reason = app.textFields["credit-reason"].exists ? app.textFields["credit-reason"] : app.textViews["credit-reason"]
            reason.tap(); reason.typeText("Higher daily usage")
            app.swipeUp()
            app.buttons["credit-save"].tap()
            XCTAssertTrue(app.staticTexts["credit-save-notice"].waitForExistence(timeout:10))
            XCTAssertTrue(app.staticTexts["Saved. 3,500 credits at the next refill."].exists)
            app.swipeDown()
        }
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Waiting for verification"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.lifetime = .keepAlways; add(attachment)
    }
}
''')
print('UI fixture generated at',out)
