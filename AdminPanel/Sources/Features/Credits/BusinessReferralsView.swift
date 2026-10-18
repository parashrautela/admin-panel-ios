import SwiftUI

struct BusinessReferralsView: View {
    var wholesalerID: String? = nil
    var retailerID: String? = nil
    var inviterName: String? = nil
    @State private var links: [ReferralRecord] = []
    @State private var count = 0
    @State private var page = 0
    @State private var loading = true
    @State private var repairing = false
    @State private var error: String?
    @State private var refreshKey = UUID()
    @State private var events: [String: [ReferralEvent]] = [:]
    @State private var historyLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text(retailerID == nil ? "Referrals" : "Referral")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Spacer()
                // A plain icon, not a bordered button: refresh is housekeeping, so it
                // shouldn't compete with the card title.
                Button { refreshKey = UUID() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.inkMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(loading || repairing)
                .accessibilityLabel("Refresh referrals")
            }
            if let inviterName, !inviterName.isEmpty {
                Text("Invited by \(inviterName)")
                    .font(.subheadline)
                    .foregroundStyle(Color.ink)
            }
            if loading { ProgressView("Loading referrals…") }
            if let error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Color.danger)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dangerBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if !loading && error == nil && links.isEmpty {
                Text(retailerID == nil ? "No referrals yet." : (inviterName == nil ? "No inviting wholesaler yet." : "No linked invitation record."))
                    .font(.subheadline)
                    .foregroundStyle(Color.inkMuted)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                    if index > 0 {
                        Divider().overlay(Color.hairlineSoft).padding(.vertical, 16)
                    }
                    referralRow(link)
                }
            }
            if count > 25 {
                HStack {
                    Button("Previous") { page -= 1 }
                        .disabled(page == 0 || loading || repairing)
                        .buttonStyle(ReferralActionButtonStyle(fillsWidth: false))
                    Spacer()
                    Text("Page \(page + 1)")
                        .font(.caption)
                        .foregroundStyle(Color.inkMuted)
                    Spacer()
                    Button("Next") { page += 1 }
                        .disabled((page + 1) * 25 >= count || loading || repairing)
                        .buttonStyle(ReferralActionButtonStyle(fillsWidth: false))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .webCard()
        .task(id: "\(wholesalerID ?? "")|\(retailerID ?? "")|\(page)|\(refreshKey)") { await load() }
    }

    /// One referral: the name and status on a single line, the amounts as label-and-value
    /// rows in an inset panel, then the actions. Each level has one clear weight.
    private func referralRow(_ link: ReferralRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                if retailerID == nil {
                    if let id = link.retailer_id {
                        NavigationLink(link.retailer_name ?? "Retailer", value: ReviewRoute(entity: .retailer, id: id))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    } else {
                        Text("Invitation not accepted")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    }
                }
                Spacer(minLength: 8)
                statusPill(link.displayStatus, status: link.status)
            }
            if wholesalerID == nil && inviterName == nil {
                Text("Invited by \(link.inviter_name ?? "Wholesaler")")
                    .font(.footnote)
                    .foregroundStyle(Color.inkMuted)
            }
            if link.policy_version == 1 {
                VStack(alignment: .leading, spacing: 10) {
                    detailRow("Retailer gift", value: "\(link.gift_credits.formatted()) credits", state: link.gift_ledger_id == nil ? "After verification" : "Paid")
                    detailRow("Wholesaler reward", value: "1,000 credits", state: link.reward_ledger_id == nil ? "After verification" : "Paid")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text("This referral keeps its original terms.")
                    .font(.footnote)
                    .foregroundStyle(Color.inkMuted)
            }
            if link.canCompleteReward, let id = link.retailer_id {
                Button("Complete pending reward") { Task { await repair(id) } }
                    .disabled(loading || repairing)
                    .buttonStyle(ReferralActionButtonStyle())
            }
            DisclosureGroup("Referral details") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Code: \(link.code)").textSelection(.enabled)
                    Text("Created: \(date(link.created_at))")
                    Text("Joined: \(date(link.accepted_at))")
                    if link.settled_at != nil { Text("Reward paid: \(date(link.settled_at))") }
                    Button("View history") { Task { await history(link.id) } }
                        .disabled(historyLoading)
                        .buttonStyle(ReferralActionButtonStyle(fillsWidth: false))
                    if let entries = events[link.id] {
                        if entries.isEmpty { Text("No recorded changes.") }
                        ForEach(entries) { event in
                            Text("\(date(event.created_at)) · \(event.event.replacingOccurrences(of: "_", with: " "))")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
            .font(.subheadline)
            .tint(Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Label on the left, value on the right with its state underneath.
    private func detailRow(_ label: String, value: String, state: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.inkMuted)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ink)
                Text(state)
                    .font(.caption)
                    .foregroundStyle(Color.inkMuted)
            }
        }
    }

    // Rewarded = success tint, pending = warning tint, every other status = surface2.
    private func statusPill(_ text: String, status: String) -> some View {
        let tone = statusTone(status)
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tone.background, in: Capsule())
    }

    private func statusTone(_ status: String) -> (text: Color, background: Color) {
        switch status {
        case "rewarded": return (Color.success, Color.successBg)
        case "pending": return (Color.warning, Color.warningBg)
        default: return (Color.inkMuted, Color.surface2)
        }
    }

    @MainActor private func load() async {
        loading = true; error = nil
        defer { if !Task.isCancelled { loading = false } }
        do {
            let result = try await AdminAPI.referrals(page: page, search: "", status: nil, wholesaler: wholesalerID, retailer: retailerID)
            guard !Task.isCancelled else { return }
            links = result.links; count = result.count
        } catch { if !Task.isCancelled { self.error = error.localizedDescription; links = []; count = 0 } }
    }
    @MainActor private func repair(_ id: String) async {
        guard !repairing else { return }; repairing = true; error = nil
        defer { repairing = false }
        do { try await AdminAPI.repairReferral(retailer: id); await load() }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func history(_ id: String) async {
        guard !historyLoading else { return }; historyLoading = true
        defer { historyLoading = false }
        do { events[id] = try await AdminAPI.referralEvents(id: id) }
        catch { self.error = error.localizedDescription }
    }
    private func date(_ raw: String?) -> String {
        guard let date = AdminRefillClock.date(raw) else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// Secondary action: white fill, hairline border, charcoal text, 10pt radius, 44pt minimum height.
private struct ReferralActionButtonStyle: ButtonStyle {
    var fillsWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        ReferralActionButtonBody(configuration: configuration, fillsWidth: fillsWidth)
    }
}

private struct ReferralActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let fillsWidth: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        // Same chrome as the dashboard buttons: one 44pt height, 8pt radius, one weight.
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil)
            .background(Color.surface1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}

struct BusinessCreditsAndReferrals: View {
    let entity: ReviewEntity
    let submission: Submission
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BusinessCreditsView(entity: entity, businessID: submission.id)
            BusinessReferralsView(wholesalerID: entity == .wholesaler ? submission.id : nil,
                retailerID: entity == .retailer ? submission.id : nil,
                inviterName: entity == .retailer ? submission.inviter_business_name : nil)
        }.id("\(entity.rawValue):\(submission.id)")
    }
}
