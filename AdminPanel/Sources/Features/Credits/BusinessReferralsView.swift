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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(retailerID == nil ? "Referrals" : "Referral").font(.headline)
                Spacer()
                Button("Refresh") { refreshKey = UUID() }.disabled(loading || repairing)
            }
            if let inviterName, !inviterName.isEmpty { Text("Invited by \(inviterName)").font(.subheadline) }
            if loading { ProgressView("Loading referrals…") }
            if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
            if !loading && error == nil && links.isEmpty {
                Text(retailerID == nil ? "No referrals yet." : (inviterName == nil ? "No inviting wholesaler yet." : "No linked invitation record."))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(links) { link in
                VStack(alignment: .leading, spacing: 10) {
                    if retailerID == nil {
                        if let id = link.retailer_id {
                            NavigationLink(link.retailer_name ?? "Retailer", value: ReviewRoute(entity: .retailer, id: id)).font(.subheadline.bold())
                        } else { Text("Invitation not accepted").font(.subheadline.bold()) }
                    }
                    if wholesalerID == nil && inviterName == nil {
                        Text("Invited by \(link.inviter_name ?? "Wholesaler")").font(.subheadline)
                    }
                    Text(link.displayStatus).font(.caption.bold()).padding(6).background(.gray.opacity(0.1), in: Capsule())
                    if link.policy_version == 1 {
                        Text("Retailer gift: \(link.gift_credits.formatted()) credits · \(link.gift_ledger_id == nil ? "After verification" : "Paid")").font(.subheadline)
                        Text("Wholesaler reward: 1,000 credits · \(link.reward_ledger_id == nil ? "After verification" : "Paid")").font(.subheadline)
                    } else { Text("This referral keeps its original terms.").font(.subheadline).foregroundStyle(.secondary) }
                    if link.canCompleteReward, let id = link.retailer_id {
                        Button("Complete pending reward") { Task { await repair(id) } }.disabled(loading || repairing).buttonStyle(.bordered)
                    }
                    DisclosureGroup("Referral details") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Code: \(link.code)").textSelection(.enabled)
                            Text("Created: \(date(link.created_at))")
                            Text("Joined: \(date(link.accepted_at))")
                            if link.settled_at != nil { Text("Reward paid: \(date(link.settled_at))") }
                            Button("View history") { Task { await history(link.id) } }.disabled(historyLoading)
                            if let entries = events[link.id] {
                                if entries.isEmpty { Text("No recorded changes.") }
                                ForEach(entries) { event in
                                    Text("\(date(event.created_at)) · \(event.event.replacingOccurrences(of: "_", with: " "))")
                                }
                            }
                        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.subheadline)
                }
                .padding(12).background(.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            if count > 25 {
                HStack {
                    Button("Previous") { page -= 1 }.disabled(page == 0 || loading || repairing)
                    Spacer(); Text("Page \(page + 1)").font(.caption); Spacer()
                    Button("Next") { page += 1 }.disabled((page + 1) * 25 >= count || loading || repairing)
                }
            }
        }
        .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.gray.opacity(0.2)))
        .task(id: "\(wholesalerID ?? "")|\(retailerID ?? "")|\(page)|\(refreshKey)") { await load() }
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
