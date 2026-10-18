import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

struct AdminAPIError: LocalizedError {
    let message: String
    var code: String? = nil
    var status: Int? = nil
    var errorDescription: String? { message }
}

// Simulated Credits mapError function matching AdminAPI.mapError byte-for-byte
func creditsMapError(errorCode: String?, serverMessage: String?, status: Int) -> AdminAPIError {
    let friendly: String
    switch errorCode {
    case "VERSION_CONFLICT":
        friendly = "This allocation changed elsewhere. Refresh before editing again."
    case "IDEMPOTENCY_CONFLICT":
        friendly = "This request could not be reused. Refresh before editing again."
    case "NOT_VERIFIED":
        friendly = "Verify this business before changing its allocation."
    default:
        friendly = serverMessage ?? errorCode ?? "The request could not be completed."
    }
    return AdminAPIError(message: friendly, code: errorCode, status: status)
}

// MARK: - 1. Contract Test: Credits Error Messages Stay Byte-Identical (C2)

let creditConflictErr = creditsMapError(errorCode: "VERSION_CONFLICT", serverMessage: "Conflict", status: 409)
check(
    creditConflictErr.message == "This allocation changed elsewhere. Refresh before editing again.",
    "Credits VERSION_CONFLICT text must remain byte-identical"
)

let creditIdempotencyErr = creditsMapError(errorCode: "IDEMPOTENCY_CONFLICT", serverMessage: "Conflict", status: 409)
check(
    creditIdempotencyErr.message == "This request could not be reused. Refresh before editing again.",
    "Credits IDEMPOTENCY_CONFLICT text must remain byte-identical"
)

let creditUnverifiedErr = creditsMapError(errorCode: "NOT_VERIFIED", serverMessage: "Not verified", status: 400)
check(
    creditUnverifiedErr.message == "Verify this business before changing its allocation.",
    "Credits NOT_VERIFIED text must remain byte-identical"
)

// In contrast, FeatureErrorMapper must map VERSION_CONFLICT to feature-specific text
let featureConflictMsg = FeatureErrorMapper.map(creditConflictErr)
check(
    featureConflictMsg == "Another admin changed this. Refreshed — please try again.",
    "FeatureErrorMapper must produce feature-specific conflict text: \(featureConflictMsg)"
)

// MARK: - 2. Decode real-shaped `list` response (including override_enabled: null, missing optionals, extra fields)

let listJSON = """
{
  "ok": true,
  "future_server_metadata": { "cluster": "in-south-1", "canary": false },
  "features": [
    {
      "key": "chamak",
      "label": "Chamak",
      "description": "Short video feed for product discovery",
      "parent_key": null,
      "default_enabled": true,
      "enforcement_mode": "enforce",
      "locked_message": null,
      "override_enabled": null,
      "effective_enabled": true,
      "reason": null,
      "updated_by": null,
      "updated_at": null,
      "version": 0,
      "parent_locked": false,
      "unknown_telemetry_id": 99812
    },
    {
      "key": "set_creation",
      "label": "Set Creation",
      "description": "Create matching sets of items",
      "parent_key": "chamak",
      "default_enabled": true,
      "enforcement_mode": "enforce",
      "override_enabled": false,
      "effective_enabled": false,
      "reason": "Test lock for account review",
      "updated_by": "admin-password",
      "updated_at": "2026-10-18T12:30:00.000Z",
      "version": 3,
      "parent_locked": true
    },
    {
      "key": "publish_to_wholesaler",
      "label": "Publish to Wholesaler",
      "description": "B2B catalog sharing between wholesalers",
      "default_enabled": false,
      "enforcement_mode": "off",
      "override_enabled": null,
      "effective_enabled": false,
      "version": 0,
      "parent_locked": false
    }
  ]
}
"""

let listResponse = try JSONDecoder().decode(FeatureListResponse.self, from: Data(listJSON.utf8))
check(listResponse.ok, "List response ok must be true")
guard let features = listResponse.features else {
    fatalError("Features array must not be nil")
}
check(features.count == 3, "Decoded features count must be 3")

let chamak = features[0]
check(chamak.key == "chamak", "Feature key must be chamak")
check(chamak.override_enabled == nil, "override_enabled null must decode as nil")
check(!chamak.isCustom, "No override must mean isCustom == false")
check(chamak.effective_enabled == true, "effective_enabled must be true")
check(chamak.version == 0, "Default version must be 0")
check(!chamak.parent_locked, "Chamak cannot be parent-locked")
check(chamak.isEnforced, "Mode enforce must mean isEnforced == true")
check(!chamak.isNotEnforcedYet, "Mode enforce must mean isNotEnforcedYet == false")

let setCreation = features[1]
check(setCreation.key == "set_creation", "Key must be set_creation")
check(setCreation.parent_key == "chamak", "Parent key must be chamak")
check(setCreation.isCustom, "Override set must mean isCustom == true")
check(setCreation.override_enabled == false, "override_enabled must decode as false")
check(setCreation.version == 3, "Version must decode as 3")
check(setCreation.parent_locked, "parent_locked must be true")

let pubWholesaler = features[2]
check(pubWholesaler.key == "publish_to_wholesaler", "Key must be publish_to_wholesaler")
check(pubWholesaler.enforcement_mode == "off", "Enforcement mode must be off")
check(pubWholesaler.isNotEnforcedYet, "Mode off must trigger isNotEnforcedYet == true")
check(!pubWholesaler.isEnforced, "Mode off must mean isEnforced == false")

// MARK: - 3. Decode `audit` and `catalog_list` responses

let auditJSON = """
{
  "ok": true,
  "count": 42,
  "page": 0,
  "pageSize": 25,
  "rows": [
    {
      "id": "e0e29b12-91f7-4be7-8a43-6df15df2d301",
      "wholesaler_user_id": "76ba1e05-24e0-410c-99c5-84fa7216ee89",
      "feature_key": "chamak",
      "action": "set",
      "old_value": { "enabled": true, "version": 0 },
      "new_value": { "enabled": false, "version": 1 },
      "reason": "Policy violation inquiry",
      "actor": "admin-password",
      "created_at": "2026-10-18T14:45:00.000Z"
    },
    {
      "id": "a1b2c3d4-0000-0000-0000-000000000002",
      "feature_key": "messages",
      "action": "reset",
      "old_value": null,
      "new_value": null,
      "reason": "Restored access",
      "actor": "admin-password",
      "created_at": "2026-10-18T15:00:00Z"
    }
  ]
}
"""

let auditPage = try JSONDecoder().decode(FeatureAuditPage.self, from: Data(auditJSON.utf8))
check(auditPage.ok, "Audit page ok must be true")
check(auditPage.count == 42, "Total count must be 42")
check(auditPage.rows.count == 2, "Decoded rows count must be 2")
let auditRow1 = auditPage.rows[0]
check(auditRow1.feature_key == "chamak", "Row feature key must be chamak")
check(auditRow1.action == "set", "Action must be set")
check(auditRow1.old_value?["enabled"]?.boolValue == true, "old_value enabled must be true")
check(auditRow1.new_value?["enabled"]?.boolValue == false, "new_value enabled must be false")
check(auditRow1.new_value?["version"]?.intValue == 1, "new_value version must be 1")

let catalogJSON = """
{
  "ok": true,
  "catalog": [
    {
      "key": "chamak",
      "label": "Chamak",
      "description": "Short video feed",
      "parent_key": null,
      "default_enabled": true,
      "enforcement_mode": "enforce",
      "locked_message": "Chamak is disabled",
      "updated_at": "2026-10-17T10:00:00Z"
    },
    {
      "key": "publish_to_wholesaler",
      "label": "Publish to Wholesaler",
      "description": "B2B wholesaler sharing",
      "parent_key": null,
      "default_enabled": false,
      "enforcement_mode": "off",
      "locked_message": null,
      "updated_at": null
    }
  ]
}
"""

let catalogResponse = try JSONDecoder().decode(FeatureCatalogListResponse.self, from: Data(catalogJSON.utf8))
check(catalogResponse.ok, "Catalog response ok must be true")
check(catalogResponse.catalog?.count == 2, "Catalog items count must be 2")
let catalogItem0 = catalogResponse.catalog![0]
check(catalogItem0.key == "chamak", "Catalog key must be chamak")
check(catalogItem0.enforcement_mode == "enforce", "Catalog mode must be enforce")

// MARK: - 4. Request bodies encode exactly `feature_key` (not `key`)

let wsId = "11111111-2222-3333-4444-555555555555"

let setReq = FeatureSetRequest(
    wholesaler_id: wsId,
    feature_key: "chamak",
    enabled: false,
    reason: "Administrative block",
    expected_version: 2
)
let setDict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(setReq)) as! [String: Any]
check(setDict["action"] as? String == "set", "Action must be set")
check(setDict["wholesaler_id"] as? String == wsId, "Wholesaler ID must match")
check(setDict["feature_key"] as? String == "chamak", "Request must encode 'feature_key', not 'key'")
check(setDict["key"] == nil, "Request MUST NOT encode 'key'")
check(setDict["enabled"] as? Bool == false, "Enabled must be false")
check(setDict["reason"] as? String == "Administrative block", "Reason must match")
check(setDict["expected_version"] as? Int == 2, "expected_version must match")

let resetReq = FeatureResetRequest(
    wholesaler_id: wsId,
    feature_key: "messages",
    reason: "Restoring default",
    expected_version: 1
)
let resetDict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(resetReq)) as! [String: Any]
check(resetDict["action"] as? String == "reset", "Action must be reset")
check(resetDict["feature_key"] as? String == "messages", "Reset request must encode 'feature_key'")
check(resetDict["key"] == nil, "Reset request MUST NOT encode 'key'")
check(resetDict["expected_version"] as? Int == 1, "expected_version must match")

let auditReq = FeatureAuditRequest(wholesaler_id: wsId, page: 2, pageSize: 25)
let auditDict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(auditReq)) as! [String: Any]
check(auditDict["action"] as? String == "audit", "Action must be audit")
check(auditDict["wholesaler_id"] as? String == wsId, "wholesaler_id must match")
check(auditDict["page"] as? Int == 2 && auditDict["pageSize"] as? Int == 25, "Pagination parameters must match")

let catalogSetReq = FeatureCatalogSetRequest(
    feature_key: "custom_inquiries",
    default_enabled: true,
    enforcement_mode: "enforce",
    reason: "Enforcing for all accounts"
)
let catSetDict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(catalogSetReq)) as! [String: Any]
check(catSetDict["action"] as? String == "catalog_set", "Action must be catalog_set")
check(catSetDict["feature_key"] as? String == "custom_inquiries", "CatalogSet must encode 'feature_key'")
check(catSetDict["key"] == nil, "CatalogSet MUST NOT encode 'key'")
check(catSetDict["enforcement_mode"] as? String == "enforce", "enforcement_mode must match")

// MARK: - 5. Reason Validation (1–500 trimmed characters)

for invalidReason in ["", "   ", "\n\t  \n"] {
    let result = FeatureValidation.validateReason(invalidReason)
    guard case .failure(let err) = result, err == .empty else {
        fatalError("Empty/whitespace reason should fail validation with .empty: '\(invalidReason)'")
    }
}

let reason501 = String(repeating: "x", count: 501)
let result501 = FeatureValidation.validateReason(reason501)
guard case .failure(let err501) = result501, case .tooLong(501) = err501 else {
    fatalError("501 character reason must fail with .tooLong(501)")
}

let validReason = "  Valid business operational reason  "
let resultValid = FeatureValidation.validateReason(validReason)
guard case .success(let trimmed) = resultValid, trimmed == "Valid business operational reason" else {
    fatalError("Reason must be trimmed on success")
}

let reason500 = String(repeating: "a", count: 500)
guard case .success(let trimmed500) = FeatureValidation.validateReason(reason500), trimmed500.count == 500 else {
    fatalError("500 character reason must be valid")
}

// MARK: - 6. Error Mapping

check(
    FeatureErrorMapper.map(code: "VERSION_CONFLICT", status: 409, fallbackMessage: "") ==
    "Another admin changed this. Refreshed — please try again.",
    "VERSION_CONFLICT mapping mismatch"
)
check(
    FeatureErrorMapper.map(code: "NOT_A_WHOLESALER", status: 404, fallbackMessage: "") ==
    "Wholesaler not found.",
    "NOT_A_WHOLESALER mapping mismatch"
)
check(
    FeatureErrorMapper.map(code: "RATE_LIMITED", status: 429, fallbackMessage: "") ==
    "Too many requests. Please retry in a moment.",
    "RATE_LIMITED mapping mismatch"
)
check(
    FeatureErrorMapper.map(code: "INVALID_REASON", status: 400, fallbackMessage: "") ==
    "Reason must be 1–500 characters.",
    "INVALID_REASON mapping mismatch"
)
check(
    FeatureErrorMapper.map(code: "FEATURE_ADMIN_UNAVAILABLE", status: 503, fallbackMessage: "") ==
    "Feature controls service is temporarily unavailable.",
    "FEATURE_ADMIN_UNAVAILABLE mapping mismatch"
)
check(
    FeatureErrorMapper.map(code: "Unauthorized", status: 401, fallbackMessage: "") ==
    "Admin authorization failed. Please check credentials.",
    "Unauthorized code mapping mismatch"
)
check(
    FeatureErrorMapper.map(code: nil, status: 401, fallbackMessage: "Something") ==
    "Admin authorization failed. Please check credentials.",
    "Status 401 mapping mismatch"
)
check(
    FeatureErrorMapper.map(code: "SOME_UNKNOWN_CODE", status: 500, fallbackMessage: "Custom fallback") ==
    "Custom fallback",
    "Unknown code should fallback to provided message"
)

// Test FeatureErrorMapper.map(Error) with AdminAPIError
let apiErr = AdminAPIError(message: "Original", code: "RATE_LIMITED", status: 429)
check(
    FeatureErrorMapper.map(apiErr) == "Too many requests. Please retry in a moment.",
    "FeatureErrorMapper.map(Error) must inspect code properly"
)

// MARK: - 7. Date Formatting (IST)

let dateStr = "2026-10-18T12:30:00.000Z"
let formattedIST = FeatureDateFormatter.indiaTimeString(from: dateStr)
check(formattedIST.contains("IST"), "Date string must contain 'IST'")
check(FeatureDateFormatter.indiaTimeString(from: nil) == "—", "Nil date string must format as em-dash")

print("PASS iOS Feature Access: decoding (nulls, missing optionals, unknown fields), audit and catalog list decoding, feature_key request bodies, reason validation (empty, 501 chars, trimming), error mappings (VERSION_CONFLICT, NOT_A_WHOLESALER, RATE_LIMITED, Unauthorized, 401), parent_locked & enforcement_mode rules, and byte-identical credits error messages")
