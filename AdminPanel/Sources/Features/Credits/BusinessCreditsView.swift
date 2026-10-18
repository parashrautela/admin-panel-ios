import SwiftUI

struct BusinessCreditsView: View {
    let entity: ReviewEntity
    let businessID: String
    @Environment(\.scenePhase) private var scenePhase
    @State private var report: CreditAllowancePage?
    @State private var clock: AdminRefillClock?
    @State private var loading = false
    @State private var saving = false
    @State private var error: String?
    @State private var notice: String?
    @State private var editing = false
    @State private var reset = false
    @State private var grantNow = false
    @State private var amount = ""
    @State private var reason = ""
    // Preserve the exact payload after a lost response. Retry never silently changes its version/key.
    @State private var pending: CreditAllowanceChange?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Credits")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Spacer()
                // Plain icon, matching the referrals card header.
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.inkMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(loading || saving || editing)
                .accessibilityLabel("Refresh credits")
            }
            if loading { ProgressView("Loading credits…") }
            if let notice {
                Text(notice)
                    .font(.subheadline)
                    .foregroundStyle(Color.success)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.successBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("credit-save-notice")
            }
            if let error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Color.danger)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dangerBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if let report, let item = report.items.first {
                HStack(alignment: .top, spacing: 16) {
                    figure("Available now", item.available.formatted())
                    figure("Credits per 24 hours", item.daily_allowance == 0 ? "Paused" : item.daily_allowance.formatted())
                }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next refill")
                            .font(.caption)
                            .foregroundStyle(Color.inkMuted)
                        Text(refillText(item))
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.ink)
                            .monospacedDigit()
                        if let date = AdminRefillClock.date(item.next_refill_at) {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(Color.inkMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if let current = item.current_allowance, current != item.daily_allowance {
                    note("Current allowance: \(current.formatted()). The new amount starts at the next refill.")
                }
                if entity == .retailer { note("Staff share this store’s credits.") }
                if !report.program_active {
                    note("Recurring credits are not active. An allocation can be scheduled for activation.")
                }
                if item.verification_status == "verified" {
                    if editing { editor(item) }
                    else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], alignment: .leading, spacing: 8) {
                            Button("Give credits now") { begin(amount: 0, reset: false, grant: true) }
                                .buttonStyle(CreditsActionButtonStyle(kind: .secondary))
                            Button("Change credits") { begin(amount: item.daily_allowance, reset: false) }
                                .buttonStyle(CreditsActionButtonStyle(kind: .primary))
                            Button("Pause credits") { begin(amount: 0, reset: false) }
                                .buttonStyle(CreditsActionButtonStyle(kind: .secondary))
                            Button("Use default (\(report.default_allowance.formatted()))") { begin(amount: report.default_allowance, reset: true) }
                                .buttonStyle(CreditsActionButtonStyle(kind: .secondary))
                        }
                    }
                } else { note("Verify this business before changing credits.", font: .subheadline) }
                DisclosureGroup("Balance details") {
                    LabeledContent("Admin bonus", value: (item.admin_available ?? 0).formatted())
                    LabeledContent("Recurring", value: item.recurring_available.formatted())
                    LabeledContent("Referral gifts", value: item.gift_available.formatted())
                    LabeledContent("Purchased", value: item.paid_available.formatted())
                }
                .font(.subheadline)
                .tint(Color.ink)
                .foregroundStyle(Color.ink)
            } else if !loading {
                note(error == nil ? "No credit account information available." : "Refresh to try again.", font: .subheadline)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .webCard()
        .task(id: "\(entity.rawValue):\(businessID)") { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !editing && !saving { Task { await load() } }
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.inkMuted)
            Text(value)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func note(_ text: String, font: Font = .caption) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(Color.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editor(_ item: CreditAllowanceItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(grantNow ? "Give credits now" : reset ? "Restore the default allowance" : "Change the next allowance")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ink)
            TextField(grantNow ? "Credits to send now" : "Credits per 24 hours", text: $amount)
                .keyboardType(.numberPad)
                .creditsFieldChrome()
                .disabled(reset || saving || pending != nil)
                .accessibilityLabel(grantNow ? "Credits to send now" : "Credits per 24 hours")
                .accessibilityIdentifier("credit-amount")
            TextField("Reason (required)", text: $reason, axis: .vertical)
                .lineLimit(2...4)
                .creditsFieldChrome()
                .disabled(saving || pending != nil)
                .accessibilityIdentifier("credit-reason")
            note(grantNow ? "Adds a one-time bonus immediately, available until spent. The allowance and refill time stay the same." : "Applies at the next refill. Current credits remain available.")
            HStack(spacing: 8) {
                Button(pending == nil ? (grantNow ? "Send credits now" : "Save credits") : "Retry same request") { Task { await save(item) } }
                    .buttonStyle(CreditsActionButtonStyle(kind: .primary, fillsWidth: false))
                    .disabled(saving || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("credit-save")
                Button("Cancel") {
                    editing = false; pending = nil
                    Task { await load() }
                }
                .buttonStyle(CreditsActionButtonStyle(kind: .secondary, fillsWidth: false))
                .disabled(saving)
                if saving { ProgressView() }
            }
        }
    }
    private func begin(amount: Int, reset: Bool, grant: Bool = false) {
        grantNow = grant
        self.amount = grant ? "" : String(amount); self.reset = reset; reason = ""; pending = nil
        error = nil; notice = nil; editing = true
    }
    private func refillText(_ item: CreditAllowanceItem) -> String {
        if item.daily_allowance == 0 { return "Paused after the current allowance" }
        guard let remaining = clock?.remaining(until: item.next_refill_at) else { return "Starts when the business next uses credits" }
        guard remaining > 0 else { return "Ready when the business next uses credits" }
        let seconds = Int(ceil(remaining))
        return String(format: "%02d:%02d:%02d remaining", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
    @MainActor private func load() async {
        guard !loading, !saving else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let result = try await AdminAPI.creditAllowance(entity: entity, id: businessID)
            guard !Task.isCancelled else { return }
            guard result.ok, result.items.first?.id == businessID,
                  let serverDate = AdminRefillClock.date(result.server_now) else {
                throw AdminAPIError(message: "Could not load this business’s credit allocation.")
            }
            report = result
            clock = AdminRefillClock(serverDate: serverDate, sampledUptime: ProcessInfo.processInfo.systemUptime)
        } catch {
            if !Task.isCancelled { report = nil; clock = nil; self.error = error.localizedDescription }
        }
    }
    @MainActor private func save(_ item: CreditAllowanceItem) async {
        guard !saving else { return }
        saving = true; error = nil
        do {
            let change: CreditAllowanceChange
            if let pending { change = pending }
            else {
                change = grantNow ? try CreditAllowanceChange.grant(entity: entity, id: businessID, amount: amount, reason: reason) : try CreditAllowanceChange.make(entity: entity, id: businessID, amount: amount,
                    reason: reason, version: item.policy_version, reset: reset)
                pending = change
            }
            if grantNow {
                let result = try await AdminAPI.giveCreditsNow(change)
                guard result.ok else { throw AdminAPIError(message: "The credits were not sent.") }
                notice = "Sent. \(result.granted.formatted()) credits are available now."
            } else {
                let result = try await AdminAPI.saveCreditAllowance(change)
                guard result.ok else { throw AdminAPIError(message: "The allocation was not saved.") }
                notice = result.next_allowance == 0 ? "Saved. Credits will pause after the current allowance." : "Saved. \(result.next_allowance.formatted()) credits at the next refill."
            }
            pending = nil; editing = false
            saving = false; await load()
        } catch {
            self.error = error.localizedDescription
            if let api = error as? AdminAPIError, api.status == 409 || api.code == "NOT_VERIFIED" {
                // A definitive rejection cannot be retried against a stale policy.
                pending = nil; editing = false; report = nil
            }
            saving = false
        }
    }
}

// Text field chrome: white field, hairline border, 10pt radius, 44pt minimum height.
private extension View {
    func creditsFieldChrome() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 16))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.surface1, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            )
    }
}

// Primary: charcoal fill with white text. Secondary: white fill with hairline border.
private struct CreditsActionButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind
    var fillsWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        CreditsActionButtonBody(configuration: configuration, kind: kind, fillsWidth: fillsWidth)
    }
}

private struct CreditsActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: CreditsActionButtonStyle.Kind
    let fillsWidth: Bool
    @Environment(\.isEnabled) private var isEnabled

    private var isPrimary: Bool { kind == .primary }

    var body: some View {
        // Same chrome as the dashboard buttons: one 44pt height, 8pt radius, one weight.
        // Long labels shrink slightly rather than wrapping onto a second line.
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isPrimary ? Color.onPrimary : Color.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil)
            .background(isPrimary ? Color.ink : Color.surface1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.hairline, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}
