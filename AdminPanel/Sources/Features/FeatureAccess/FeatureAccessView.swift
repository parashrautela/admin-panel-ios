import SwiftUI

struct FeatureAccessView: View {
    let wholesalerID: String

    @Environment(\.scenePhase) private var scenePhase
    @State private var features: [FeatureFlag] = []
    @State private var loading = false
    @State private var saving = false
    @State private var error: String?
    @State private var notice: String?

    // Inline form state: exactly one form open at a time, positioned directly under its feature row
    struct PendingForm: Equatable {
        let featureKey: String
        let targetEnabled: Bool
        let isReset: Bool
        let isTurningOff: Bool
    }

    @State private var pendingForm: PendingForm?
    @State private var typedReason = ""
    @State private var formError: String?

    // Sheets
    @State private var showHistory = false
    @State private var showDefaults = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection

            if loading && features.isEmpty {
                ProgressView("Loading feature access…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let notice {
                Text(notice)
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("feature-notice")
            }

            if let error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("feature-error")
            }

            if !features.isEmpty {
                VStack(spacing: 10) {
                    ForEach(features) { feature in
                        featureRow(feature)
                    }
                }
            } else if !loading && error != nil {
                Button("Retry loading features") {
                    Task { await loadFeatures() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
        .task(id: wholesalerID) {
            await loadFeatures()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !saving && pendingForm == nil {
                Task { await loadFeatures() }
            }
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                FeatureHistoryView(wholesalerID: wholesalerID)
            }
        }
        .sheet(isPresented: $showDefaults) {
            NavigationStack {
                FeatureGlobalDefaultsView()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Feature Access")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Configure per-wholesaler feature availability and global enforcement modes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    headerButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    headerButtons
                }
            }
        }
    }

    @ViewBuilder
    private var headerButtons: some View {
        Button("History") {
            showHistory = true
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
        .disabled(loading || saving)
        .accessibilityIdentifier("feature-history-button")

        Button("Global defaults") {
            showDefaults = true
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
        .disabled(loading || saving)
        .accessibilityIdentifier("feature-defaults-button")

        Button("Refresh") {
            Task { await loadFeatures() }
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
        .disabled(loading || saving)
        .accessibilityIdentifier("feature-refresh-button")
    }

    // MARK: - Feature Row

    private func featureRow(_ feature: FeatureFlag) -> some View {
        let isThisFormOpen = pendingForm?.featureKey == feature.key
        let isTurningOff = pendingForm?.isTurningOff == true && isThisFormOpen

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(feature.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        if feature.isCustom {
                            badgeText("Custom", background: Color.orange.opacity(0.15), foreground: .orange)
                        }

                        if feature.isNotEnforcedYet {
                            badgeText("Not enforced yet", background: Color.gray.opacity(0.15), foreground: .secondary)
                        }

                        if feature.parent_locked {
                            badgeText("Locked (Chamak off)", background: Color.red.opacity(0.15), foreground: .red)
                        }
                    }

                    Text(feature.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if feature.isCustom, let reason = feature.reason, !reason.isEmpty {
                        Text("Override reason: \(reason)\(feature.updated_at.map { " · " + FeatureDateFormatter.indiaTimeString(from: $0) } ?? "")")
                            .font(.caption2)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if feature.isCustom {
                    Button("Reset to default") {
                        openInlineForm(for: feature, targetEnabled: feature.default_enabled, isReset: true)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(saving || feature.parent_locked)
                    .accessibilityIdentifier("feature-reset-\(feature.key)")
                }

                // C3: SwiftUI Toggle flips its value on tap. Custom binding ensures switch never changes before server confirmation.
                Toggle(
                    isOn: Binding(
                        get: { feature.effective_enabled },
                        set: { _ in
                            openInlineForm(for: feature, targetEnabled: !feature.effective_enabled, isReset: false)
                        }
                    )
                ) {
                    EmptyView()
                }
                .labelsHidden()
                .disabled(saving || feature.parent_locked)
                .accessibilityLabel("\(feature.label), \(feature.effective_enabled ? "on" : "off"). Double tap to change.")
                .accessibilityIdentifier("feature-toggle-\(feature.key)")
            }
            .padding(12)

            // Inline confirmation form expands directly under this row
            if isThisFormOpen, let form = pendingForm {
                Divider()
                inlineForm(feature: feature, form: form)
                    .padding(12)
                    .background(isTurningOff ? Color.red.opacity(0.06) : Color.gray.opacity(0.06))
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isThisFormOpen
                        ? (isTurningOff ? Color.red.opacity(0.5) : Color.primary.opacity(0.3))
                        : (feature.parent_locked ? Color.gray.opacity(0.15) : Color.gray.opacity(0.25)),
                    lineWidth: 1
                )
        )
    }

    private func badgeText(_ text: String, background: Color, foreground: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Inline Form

    private func inlineForm(feature: FeatureFlag, form: PendingForm) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(formTitle(feature: feature, form: form))
                .font(.subheadline.bold())
                .foregroundStyle(form.isTurningOff ? Color.red : Color.primary)

            if form.isTurningOff && feature.key == "chamak" {
                Text("Turning Chamak off also turns Set Creation off.")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Reason (required)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField("Why are you making this change?", text: $typedReason, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .disabled(saving)
                    .accessibilityIdentifier("feature-reason-\(feature.key)")
            }

            if let formError {
                Text(formError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("feature-form-error-\(feature.key)")
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        await executeChange(
                            wholesalerID: wholesalerID,
                            feature: feature,
                            targetEnabled: form.targetEnabled,
                            isReset: form.isReset,
                            reason: typedReason
                        )
                    }
                } label: {
                    if saving {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Saving…")
                        }
                    } else {
                        Text(formPrimaryActionTitle(feature: feature, form: form))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(form.isTurningOff ? .red : .accentColor)
                .disabled(saving || typedReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("feature-confirm-\(feature.key)")

                Button("Cancel") {
                    closeInlineForm()
                }
                .buttonStyle(.bordered)
                .disabled(saving)
                .accessibilityIdentifier("feature-cancel-\(feature.key)")
            }
        }
    }

    private func formTitle(feature: FeatureFlag, form: PendingForm) -> String {
        if form.isReset {
            return "Reset \(feature.label) to default?"
        } else if form.targetEnabled {
            return "Turn \(feature.label) on?"
        } else {
            return "Turn \(feature.label) off for this wholesaler?"
        }
    }

    private func formPrimaryActionTitle(feature: FeatureFlag, form: PendingForm) -> String {
        if form.isReset {
            return "Reset"
        } else if form.targetEnabled {
            return "Turn \(feature.label) on"
        } else {
            return "Turn \(feature.label) off"
        }
    }

    // MARK: - Actions

    private func openInlineForm(for feature: FeatureFlag, targetEnabled: Bool, isReset: Bool) {
        if saving { return }
        notice = nil
        error = nil
        formError = nil
        typedReason = ""
        pendingForm = PendingForm(
            featureKey: feature.key,
            targetEnabled: targetEnabled,
            isReset: isReset,
            isTurningOff: !isReset && !targetEnabled
        )
    }

    private func closeInlineForm() {
        pendingForm = nil
        typedReason = ""
        formError = nil
    }

    private func loadFeatures() async {
        loading = true
        error = nil
        do {
            features = try await AdminAPI.featureFlags(wholesalerID: wholesalerID)
        } catch {
            self.error = FeatureErrorMapper.map(error)
        }
        loading = false
    }

    private func executeChange(
        wholesalerID: String,
        feature: FeatureFlag,
        targetEnabled: Bool,
        isReset: Bool,
        reason: String
    ) async {
        let validation = FeatureValidation.validateReason(reason)
        guard case .success(let trimmedReason) = validation else {
            if case .failure(let valErr) = validation {
                formError = valErr.localizedDescription
            }
            return
        }

        saving = true
        formError = nil
        notice = nil

        do {
            if isReset {
                try await AdminAPI.resetFeatureFlag(
                    wholesalerID: wholesalerID,
                    featureKey: feature.key,
                    reason: trimmedReason,
                    expectedVersion: feature.version
                )
                notice = "Reset \(feature.label) to default."
            } else {
                try await AdminAPI.setFeatureFlag(
                    wholesalerID: wholesalerID,
                    featureKey: feature.key,
                    enabled: targetEnabled,
                    reason: trimmedReason,
                    expectedVersion: feature.version
                )
                notice = "\(feature.label) turned \(targetEnabled ? "on" : "off")."
            }
            closeInlineForm()
            await loadFeatures()
        } catch {
            let mapped = FeatureErrorMapper.map(error)
            if let apiError = error as? AdminAPIError, apiError.code == "VERSION_CONFLICT" {
                closeInlineForm()
                await loadFeatures()
                self.error = mapped
            } else {
                self.formError = mapped
            }
        }
        saving = false
    }
}
