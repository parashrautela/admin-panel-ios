import SwiftUI

struct FeatureHistoryView: View {
    let wholesalerID: String?

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [FeatureAuditRow] = []
    @State private var totalCount: Int = 0
    @State private var currentPage: Int = 0
    @State private var loading = false
    @State private var loadingMore = false
    @State private var error: String?

    private let pageSize = 25

    var body: some View {
        Group {
            if loading && rows.isEmpty {
                ProgressView("Loading audit log…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, rows.isEmpty {
                VStack(spacing: 12) {
                    Text(error)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadInitial() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                ContentUnavailableView(
                    "No Audit Events",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("No feature flag modifications recorded for this wholesaler.")
                )
            } else {
                List {
                    ForEach(rows) { row in
                        auditRowView(row)
                    }

                    if rows.count < totalCount {
                        HStack {
                            Spacer()
                            if loadingMore {
                                ProgressView()
                                    .padding(.vertical, 8)
                            } else {
                                Button("Load more (\(rows.count) of \(totalCount))") {
                                    Task { await loadNextPage() }
                                }
                                .font(.subheadline)
                                .buttonStyle(.bordered)
                                .padding(.vertical, 8)
                            }
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Feature Flag Audit Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .task {
            await loadInitial()
        }
    }

    private func auditRowView(_ row: FeatureAuditRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(row.feature_key)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Spacer()

                Text(FeatureDateFormatter.indiaTimeString(from: row.created_at))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(actionDescription(for: row))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(actionBackground(for: row))
                    .foregroundStyle(actionForeground(for: row))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                if let actor = row.actor, !actor.isEmpty {
                    Text("by \(actor)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let reason = row.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func actionDescription(for row: FeatureAuditRow) -> String {
        switch row.action {
        case "set":
            if let enabled = row.new_value?["enabled"]?.boolValue {
                return enabled ? "Turned ON" : "Turned OFF"
            }
            return "Set"
        case "reset":
            return "Reset to default"
        case "catalog_default":
            if let def = row.new_value?["default_enabled"]?.boolValue {
                return "Global Default: \(def ? "ON" : "OFF")"
            }
            return "Global Default Changed"
        case "catalog_mode":
            if let mode = row.new_value?["enforcement_mode"]?.stringValue {
                return "Global Mode: \(mode.uppercased())"
            }
            return "Global Mode Changed"
        default:
            return row.action.uppercased()
        }
    }

    private func actionBackground(for row: FeatureAuditRow) -> Color {
        if row.action == "set" {
            if let enabled = row.new_value?["enabled"]?.boolValue {
                return enabled ? Color.green.opacity(0.15) : Color.red.opacity(0.15)
            }
        }
        return Color.gray.opacity(0.15)
    }

    private func actionForeground(for row: FeatureAuditRow) -> Color {
        if row.action == "set" {
            if let enabled = row.new_value?["enabled"]?.boolValue {
                return enabled ? .green : .red
            }
        }
        return .primary
    }

    private func loadInitial() async {
        loading = true
        error = nil
        currentPage = 0
        do {
            let page = try await AdminAPI.featureFlagAudit(
                wholesalerID: wholesalerID,
                page: 0,
                pageSize: pageSize
            )
            rows = page.rows
            totalCount = page.count ?? page.rows.count
        } catch {
            self.error = FeatureErrorMapper.map(error)
        }
        loading = false
    }

    private func loadNextPage() async {
        guard !loadingMore else { return }
        loadingMore = true
        let nextPage = currentPage + 1
        do {
            let page = try await AdminAPI.featureFlagAudit(
                wholesalerID: wholesalerID,
                page: nextPage,
                pageSize: pageSize
            )
            rows.append(contentsOf: page.rows)
            totalCount = page.count ?? rows.count
            currentPage = nextPage
        } catch {
            // Keep existing rows if pagination fails
        }
        loadingMore = false
    }
}
