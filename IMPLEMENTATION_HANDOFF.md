# iOS admin implementation handoff

This branch contains the native iPhone and iPad implementation completed on 8 September 2026.

Use the `AdminPanelPreview` scheme in a Debug build to run the complete interface against fictional, in-memory review data. Preview mode is excluded from Release builds. The normal app expects a new `admin-v2` backend contract; that backend is intentionally not included or deployed on this branch.

Included: adaptive queue and review UI, search/filter/sort/pagination, document viewing and comparison, assessment-gated decisions, notes, assignments, saved views, privacy curtain, named-session/MFA client flow, system-health UI, unit tests, and iPhone/iPad UI smoke tests.

Before production: implement the authenticated server API, transactional audit trail, private signed-document service, actual administrator provisioning and MFA enforcement; migrate or disable legacy shared-password endpoints; then complete staging, physical-device, accessibility, security, operator, and rollback validation. No real applicant data was used or changed for this implementation.
