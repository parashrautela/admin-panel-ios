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
                    .foregroundStyle(Color.success)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.successBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("feature-notice")
            }

            if let error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Color.danger)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dangerBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .buttonStyle(FeatureActionButtonStyle(kind: .secondary, fillsWidth: false))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .webCard()
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
                    .background(Color.canvas.ignoresSafeArea())
            }
        }
        .sheet(isPresented: $showDefaults) {
            NavigationStack {
                FeatureGlobalDefaultsView()
                    .background(Color.canvas.ignoresSafeArea())
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Feature Access")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text("Turn features on or off for this wholesaler. A switch only blocks anything when its feature is enforced.")
                        .font(.caption)
                        .foregroundStyle(Color.inkMuted)
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
        .buttonStyle(FeatureActionButtonStyle(kind: .secondary, fillsWidth: false))
        .disabled(loading || saving)
        .accessibilityIdentifier("feature-history-button")

        Button("Global defaults") {
            showDefaults = true
        }
        .buttonStyle(FeatureActionButtonStyle(kind: .secondary, fillsWidth: false))
        .disabled(loading || saving)
        .accessibilityIdentifier("feature-defaults-button")

        Button("Refresh") {
            Task { await loadFeatures() }
        }
        .buttonStyle(FeatureActionButtonStyle(kind: .secondary, fillsWidth: false))
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.ink)

                        if feature.isCustom {
                            badgeText("Custom", background: Color.warningBg, foreground: Color.warning)
                        }

                        if feature.isNotEnforcedYet {
                            badgeText("Not enforced yet", background: Color.surface2, foreground: Color.inkMuted)
                        }

                        if feature.parent_locked {
                            badgeText("Locked (Chamak off)", background: Color.dangerBg, foreground: Color.danger)
                        }
                    }

                    Text(feature.description)
                        .font(.caption)
                        .foregroundStyle(Color.inkMuted)

                    if feature.isCustom, let reason = feature.reason, !reason.isEmpty {
                        Text("Override reason: \(reason)\(feature.updated_at.map { " · " + FeatureDateFormatter.indiaTimeString(from: $0) } ?? "")")
                            .font(.caption2)
                            .italic()
                            .foregroundStyle(Color.inkSubtle)
                    }
                }

                Spacer()

                if feature.isCustom {
                    Button("Reset to default") {
                        openInlineForm(for: feature, targetEnabled: feature.default_enabled, isReset: true)
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.inkMuted)
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
                .tint(Color.ink)
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
                    .background(isTurningOff ? Color.dangerBg : Color.surface1)
            }
        }
        .background(Color.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isThisFormOpen
                        ? (isTurningOff ? Color.danger.opacity(0.6) : Color.ink.opacity(0.4))
                        : Color.hairline,
                    lineWidth: 1
                )
        )
        .opacity(feature.parent_locked ? 0.7 : 1)
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
                .foregroundStyle(form.isTurningOff ? Color.danger : Color.ink)

            if form.isTurningOff && feature.key == "chamak" {
                Text("Turning Chamak off also turns Set Creation off.")
                    .font(.caption.bold())
                    .foregroundStyle(Color.danger)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Reason (required)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.inkMuted)

                TextField("Why are you making this change?", text: $typedReason, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.subheadline)
                    .foregroundStyle(Color.ink)
                    .padding(10)
                    .background(Color.surface1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.hairline, lineWidth: 1))
                    .disabled(saving)
                    .accessibilityIdentifier("feature-reason-\(feature.key)")
            }

            if let formError {
                Text(formError)
                    .font(.caption)
                    .foregroundStyle(Color.danger)
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
                .buttonStyle(FeatureActionButtonStyle(kind: form.isTurningOff ? .danger : .primary))
                .disabled(saving || typedReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("feature-confirm-\(feature.key)")

                Button("Cancel") {
                    closeInlineForm()
                }
                .buttonStyle(FeatureActionButtonStyle(kind: .secondary))
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

// Matches the Credits card's buttons: 44pt height, 8pt radius, one weight.
// Primary is charcoal, secondary is white with a hairline, danger is red.
struct FeatureActionButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }
    var kind: Kind
    var fillsWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        FeatureActionButtonBody(configuration: configuration, kind: kind, fillsWidth: fillsWidth)
    }
}

private struct FeatureActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: FeatureActionButtonStyle.Kind
    let fillsWidth: Bool
    @Environment(\.isEnabled) private var isEnabled

    private var fill: Color {
        switch kind {
        case .primary: return .ink
        case .secondary: return .surface1
        case .danger: return .danger
        }
    }

    var body: some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(kind == .secondary ? Color.ink : Color.onPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.hairline, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}
