import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
let id = "11111111-1111-4111-8111-111111111111"
let key = "22222222-2222-4222-8222-222222222222"
for role in ReviewEntity.allCases {
    let request = try CreditAllowanceChange.make(entity: role, id: id, amount: "3500", reason: " Higher usage ", version: 7, reset: false, requestKey: key)
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
    check(json["business_type"] as? String == role.rawValue, "Correct business role required")
    check(json["wholesaler_id"] as? String == id, "Shared contract uses business ID in wholesaler_id")
    check(json["expected_version"] as? Int == 7 && json["request_key"] as? String == key, "Version/replay contract must survive encoding")
    check(json["daily_allowance"] as? Int == 3500 && json["reason"] as? String == "Higher usage", "Allocation payload must match exact user edit")
    let sameRetry = try JSONEncoder().encode(request)
    let retryJSON = try JSONSerialization.jsonObject(with: sameRetry) as! [String: Any]
    check(retryJSON["request_key"] as? String == key, "Lost-response retry retains its key")
}
for input in ["-1", "100001", "1.5", "", "abc"] {
    do { _ = try CreditAllowanceChange.make(entity: .retailer, id: id, amount: input, reason: "Change", version: 0, reset: false); fatalError("Invalid amount accepted: \(input)") }
    catch is CreditInputError { }
}
for note in ["  ", String(repeating: "a", count: 501)] {
    do { _ = try CreditAllowanceChange.make(entity: .wholesaler, id: id, amount: "2000", reason: note, version: 0, reset: false); fatalError("Invalid reason accepted") }
    catch is CreditInputError { }
}
for amount in ["0", "100000"] {
    let request = try CreditAllowanceChange.make(entity: .retailer, id: id, amount: amount, reason: "Boundary", version: 0, reset: false)
    check(request.daily_allowance == Int(amount), "Pause and maximum must be accepted")
}
let reset = try CreditAllowanceChange.make(entity: .retailer, id: id, amount: "", reason: "Default", version: 2, reset: true)
let resetJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reset)) as! [String: Any]
check(resetJSON["action"] as? String == "reset_default" && resetJSON["daily_allowance"] == nil, "Reset inherits default instead of copying it")
let pageJSON = """
{"ok":true,"items":[{"wholesaler_id":"\(id)","verification_status":"verified","daily_allowance":3500,"is_custom":true,"policy_version":7,"current_allowance":2000,"next_refill_at":"2026-10-11T23:59:00.000+00:00","recurring_available":1900,"gift_available":1000,"paid_available":68,"available":2968}],"server_now":"2026-10-10T23:59:00Z","program_active":true,"default_allowance":2000}
"""
let page = try JSONDecoder().decode(CreditAllowancePage.self, from: Data(pageJSON.utf8))
check(page.items[0].current_allowance == 2000 && page.items[0].daily_allowance == 3500, "Current grant and scheduled allowance remain separate")
let clock = AdminRefillClock(serverDate: AdminRefillClock.date(page.server_now)!, sampledUptime: 100)
check(clock.remaining(until: page.items[0].next_refill_at, uptime: 100) == 86400, "Midnight must not shorten the full 24 hours")
check(clock.remaining(until: page.items[0].next_refill_at, uptime: 86500) == 0, "Deadline clamps to ready rather than becoming negative")
check(clock.remaining(until: nil) == nil, "No issuance has no invented countdown")
check(clock.remaining(until: page.items[0].next_refill_at, uptime: 3700) == 82800, "Countdown advances from uptime without the device wall clock")
for (status, policy, expected, eligible) in [("pending",1,"Waiting for verification",false),("rewarded",1,"Reward paid",false),("legacy",0,"Original referral",false),("pending",1,"Waiting for verification",true)] {
    let raw = """
    {"id":"\(id)","code":"SAMPLE","wholesaler_id":"\(id)","retailer_id":"\(id)","retailer_status":"\(eligible ? "verified" : "pending")","status":"\(status)","policy_version":\(policy),"gift_credits":1000,"extra_credits":0,"funding_state":"reserved","refunded_credits":0,"created_at":"2026-10-10T00:00:00Z"}
    """
    let link = try JSONDecoder().decode(ReferralRecord.self, from: Data(raw.utf8))
    check(link.displayStatus == expected, "Referral status should use readable wording")
    check(link.canCompleteReward == eligible, "Only verified modern reserved rewards can be completed")
}
print("PASS iOS admin: both role payloads, version/replay keys, allocation boundaries, reason validation, default inheritance, backend decoding, 24-hour monotonic deadlines and referral eligibility")

if CommandLine.arguments.count > 1 {
    let live = try JSONDecoder().decode([String: CreditAllowancePage].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
    check(live.keys.sorted() == ["retailer", "wholesaler"], "Both live role responses required")
    for result in live.values {
        check(result.ok && result.program_active && result.items.count == 1, "Live reports must decode successfully")
        check(AdminRefillClock.date(result.server_now) != nil, "Live server timestamps must parse")
    }
    print("PASS sanitized live production allocation responses decode in iOS for both business roles")
}

for role in ReviewEntity.allCases {
    let immediate = try CreditAllowanceChange.grant(entity: role, id: id, amount: "700", reason: "Support")
    let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(immediate)) as! [String: Any]
    check(payload["action"] as? String == "grant_now" && payload["business_type"] as? String == role.rawValue, "Immediate grant selects the correct business")
    check(payload["credits"] as? Int == 700 && payload["daily_allowance"] == nil, "Immediate grant cannot change the recurring allowance")
    check(UUID(uuidString:immediate.request_key) != nil, "Immediate grant has a replay UUID")
}
do { _ = try CreditAllowanceChange.grant(entity: .retailer, id: id, amount: "0", reason: "Support"); fatalError("Zero bonus accepted") }
catch is CreditInputError { }
print("PASS iOS immediate grants: correct role, positive amount, reason and stable request key; no recurring allocation field")
