# iOS admin credits and referrals

The iOS admin uses the same live password-gated Edge Functions as the web panel. Both wholesaler and retailer cards now contain **Credits & referrals**. The business review page contains the same controls.

Each credit card displays the available balance, allowance per 24 hours, next refill and current-versus-next allowance when they differ. Change credits, Pause credits and Use default require a reason. Allocation edits apply at the next eligible refill and preserve issued grants, purchased credits and gifts. Retailer staff share their store owner's wallet. The countdown follows server time plus elapsed uptime, so changing the device clock cannot change eligibility. Database eligibility remains authoritative.

Mutations send the selected business type and ID, the policy version and a request UUID. Lost-response retries reuse the exact payload. Definitive version conflicts require refreshing instead of overwriting another administrator's edit. Unverified businesses cannot be edited. Errors are visible and unavailable reports disable allocation controls.

Referral cards use business names and simple verification/reward statuses, with codes and history collapsed. Original invitations retain their original terms. Only verified modern invitations with reserved funding offer Complete pending reward. Existing verification/rejection actions continue through the shared atomic backend review handler. No service-role credential or production login bypass was introduced.

The dashboard now uses expandable business cards on both iPhone and iPad. Canceled or outdated dashboard loads cannot replace the active business tab's results. Document review and unrelated admin actions retain their existing behavior.

## Validation

The production application builds successfully for the iOS simulator using Xcode. Foundation contract checks verify both business role payloads, amount/reason validation, pause/default semantics, replay keys and versions, current/next grant decoding, full 24-hour monotonic windows and referral eligibility. Sanitized live production responses for both business types also decode successfully. The real SwiftUI simulator UI test passed for wholesaler and retailer allocation edits and referral status (one test, zero failures).

```sh
swiftc -module-cache-path /private/tmp/jewel-admin-swift-cache \
  AdminPanel/Sources/Core/Models.swift \
  AdminPanel/Sources/Core/CreditAllowanceModels.swift \
  tests/credits-referrals/main.swift -o /private/tmp/jewel-admin-credits-contract-tests
/private/tmp/jewel-admin-credits-contract-tests

xcodebuild -project AdminPanel.xcodeproj -scheme AdminPanel \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/jewel-admin-ios-credits-build CODE_SIGNING_ALLOWED=NO build
```

`tests/credits-referrals/make-ui-fixture.py /private/tmp/jewel-admin-ios-ui-fixture` creates a separate sample app and UI-test scheme using the actual SwiftUI feature screens. The fixture replaces transport and the entry point only in its temporary directory; it does not change production authentication or write customer balances. Run XcodeGen and `xcodebuild test` against that separate project and an installed simulator.

## Distribution

These are native app changes, so updating the web deployment does not update installed iOS binaries. A signed TestFlight/App Store build is required to deliver this version to administrators' phones. This task builds and validates the source; no new App Store submission or TestFlight upload has been made. The shared backend is already live and does not need another migration for this iOS update.
