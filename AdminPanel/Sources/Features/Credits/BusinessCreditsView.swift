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
    @State private var amount = ""
    @State private var reason = ""
    // Preserve the exact payload after a lost response. Retry never silently changes its version/key.
    @State private var pending: CreditAllowanceChange?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Credits").font(.headline)
                Spacer()
                Button("Refresh") { Task { await load() } }.disabled(loading || saving || editing)
            }
            if loading { ProgressView("Loading credits…") }
            if let notice { Text(notice).font(.subheadline).foregroundStyle(.green).accessibilityIdentifier("credit-save-notice") }
            if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
            if let report, let item = report.items.first {
                LabeledContent("Available now", value: item.available.formatted())
                LabeledContent("Credits per 24 hours", value: item.daily_allowance == 0 ? "Paused" : item.daily_allowance.formatted())
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next refill").font(.subheadline).foregroundStyle(.secondary)
                        Text(refillText(item)).font(.subheadline)
                        if let date = AdminRefillClock.date(item.next_refill_at) {
                            Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let current = item.current_allowance, current != item.daily_allowance {
                    Text("Current allowance: \(current.formatted()). The new amount starts at the next refill.").font(.caption).foregroundStyle(.secondary)
                }
                if entity == .retailer { Text("Staff share this store’s credits.").font(.caption).foregroundStyle(.secondary) }
                if !report.program_active {
                    Text("Recurring credits are not active. An allocation can be scheduled for activation.").font(.caption).foregroundStyle(.secondary)
                }
                if item.verification_status == "verified" {
                    if editing { editor(item) }
                    else {
                        ViewThatFits(in: .horizontal) {
                            HStack { actions(item, defaultAmount: report.default_allowance) }
                            VStack(alignment: .leading, spacing: 12) { actions(item, defaultAmount: report.default_allowance) }
                        }
                        .buttonStyle(.bordered)
                    }
                } else { Text("Verify this business before changing credits.").font(.subheadline).foregroundStyle(.secondary) }
                DisclosureGroup("Balance details") {
                    LabeledContent("Recurring", value: item.recurring_available.formatted())
                    LabeledContent("Referral gifts", value: item.gift_available.formatted())
                    LabeledContent("Purchased", value: item.paid_available.formatted())
                }.font(.subheadline)
            } else if !loading {
                Text(error == nil ? "No credit account information available." : "Refresh to try again.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.gray.opacity(0.2)))
        .task(id: "\(entity.rawValue):\(businessID)") { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !editing && !saving { Task { await load() } }
        }
    }

    @ViewBuilder private func actions(_ item: CreditAllowanceItem, defaultAmount: Int) -> some View {
        Button("Change credits") { begin(amount: item.daily_allowance, reset: false) }
        Button("Pause credits") { begin(amount: 0, reset: false) }
        Button("Use default (\(defaultAmount.formatted()))") { begin(amount: defaultAmount, reset: true) }
    }
    private func editor(_ item: CreditAllowanceItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(reset ? "Restore the default allowance" : "Change the next allowance").font(.subheadline.bold())
            TextField("Credits per 24 hours", text: $amount).keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder).disabled(reset || saving || pending != nil)
                .accessibilityLabel("Credits per 24 hours").accessibilityIdentifier("credit-amount")
            TextField("Reason (required)", text: $reason, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...4).disabled(saving || pending != nil)
                .accessibilityIdentifier("credit-reason")
            Text("Applies at the next refill. Current credits remain available.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(pending == nil ? "Save credits" : "Retry same request") { Task { await save(item) } }
                    .buttonStyle(.borderedProminent).disabled(saving || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("credit-save")
                Button("Cancel") {
                    editing = false; pending = nil
                    Task { await load() }
                }.disabled(saving)
                if saving { ProgressView() }
            }
        }
    }
    private func begin(amount: Int, reset: Bool) {
        self.amount = String(amount); self.reset = reset; reason = ""; pending = nil
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
                change = try CreditAllowanceChange.make(entity: entity, id: businessID, amount: amount,
                    reason: reason, version: item.policy_version, reset: reset)
                pending = change
            }
            let result = try await AdminAPI.saveCreditAllowance(change)
            guard result.ok else { throw AdminAPIError(message: "The allocation was not saved.") }
            pending = nil; editing = false
            notice = result.next_allowance == 0 ? "Saved. Credits will pause after the current allowance." : "Saved. \(result.next_allowance.formatted()) credits at the next refill."
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
