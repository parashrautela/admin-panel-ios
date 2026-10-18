import SwiftUI

struct FeatureGlobalDefaultsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var items: [FeatureCatalogItem] = []
    @State private var loading = false
    @State private var saving = false
    @State private var error: String?
    @State private var notice: String?

    // Editing state: only one item edited at a time, inline under that item
    @State private var editingKey: String?
    @State private var selectedMode: String = "off"
    @State private var selectedDefault: Bool = true
    @State private var typedReason: String = ""
    @State private var confirmKeyInput: String = ""
    @State private var editError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Explanation banner
                VStack(alignment: .leading, spacing: 6) {
                    Text("System defaults and enforcement modes")
                        .font(.headline)
                    Text("This affects every wholesaler. A wholesaler's switch only blocks anything when the mode is enforce.")
                        .font(.subheadline)
                        .foregroundStyle(Color.inkMuted)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface1, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                if let notice {
                    Text(notice)
                        .font(.subheadline)
                        .foregroundStyle(Color.success)
                        .padding(.horizontal, 4)
                        .accessibilityIdentifier("catalog-notice")
                }

                if let error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(Color.danger)
                        .padding(.horizontal, 4)
                        .accessibilityIdentifier("catalog-error")
                }

                if loading && items.isEmpty {
                    ProgressView("Loading global catalog…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                } else {
                    VStack(spacing: 12) {
                        ForEach(items) { item in
                            catalogItemCard(item)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Global Feature Catalog")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .task {
            await loadCatalog()
        }
    }

    private func catalogItemCard(_ item: FeatureCatalogItem) -> some View {
        let isEditing = editingKey == item.key

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(item.label) (\(item.key))")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.ink)

                        Text(item.description)
                            .font(.caption)
                            .foregroundStyle(Color.inkMuted)
                    }

                    Spacer()

                    modeBadge(item.enforcement_mode)
                }

                HStack(spacing: 12) {
                    Text("Default: \(item.default_enabled ? "ON" : "OFF")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(item.default_enabled ? .green : .secondary)

                    Spacer()

                    if !isEditing {
                        Button("Configure Global Defaults") {
                            startEditing(item)
                        }
                        .font(.caption.weight(.medium))
                        .buttonStyle(FeatureActionButtonStyle(kind: .secondary, fillsWidth: false))
                        .disabled(saving)
                        .accessibilityIdentifier("catalog-edit-\(item.key)")
                    }
                }
            }
            .padding(14)

            if isEditing {
                Divider()
                inlineCatalogEditor(item)
                    .padding(14)
                    .background(Color.warningBg)
            }
        }
        .background(Color.surface1, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isEditing ? Color.warning.opacity(0.6) : Color.hairline,
                    lineWidth: 1
                )
        )
    }

    private func modeBadge(_ mode: String) -> some View {
        let (bg, fg): (Color, Color) = {
            switch mode {
            case "enforce": return (Color.dangerBg, Color.danger)
            case "log": return (Color.warningBg, Color.warning)
            default: return (Color.surface2, Color.inkMuted)
            }
        }()

        return Text("MODE: \(mode.uppercased())")
            .font(.caption2.monospaced().bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func inlineCatalogEditor(_ item: FeatureCatalogItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit global default: \(item.label)")
                .font(.subheadline.bold())
                .foregroundStyle(Color.ink)

            if item.key == "chamak" {
                Text("Set Creation has its own mode — change it too.")
                    .font(.caption.bold())
                    .foregroundStyle(Color.warning)
            }

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Default State")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.inkMuted)
                    Picker("Default State", selection: $selectedDefault) {
                        Text("Enabled by default").tag(true)
                        Text("Disabled by default").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Enforcement Mode")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.inkMuted)
                    Picker("Enforcement Mode", selection: $selectedMode) {
                        Text("off (no enforcement)").tag("off")
                        Text("log (log only)").tag("log")
                        Text("enforce (block actions)").tag("enforce")
                    }
                    .pickerStyle(.segmented)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Reason (required)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.inkMuted)
                TextField("Why are you updating the global configuration?", text: $typedReason, axis: .vertical)
                    .padding(10)
                    .background(Color.surface1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.hairline, lineWidth: 1))
                    .lineLimit(2...3)
                    .disabled(saving)
                    .accessibilityIdentifier("catalog-reason-\(item.key)")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Type \"\(item.key)\" to confirm global change")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.inkMuted)
                TextField(item.key, text: $confirmKeyInput)
                    .padding(10)
                    .background(Color.surface1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.hairline, lineWidth: 1))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .disabled(saving)
                    .accessibilityIdentifier("catalog-confirm-key-\(item.key)")
            }

            if let editError {
                Text(editError)
                    .font(.caption)
                    .foregroundStyle(Color.danger)
                    .accessibilityIdentifier("catalog-form-error-\(item.key)")
            }

            HStack(spacing: 8) {
                Button {
                    Task { await saveCatalogItem(item) }
                } label: {
                    if saving {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Updating…")
                        }
                    } else {
                        Text("Save Global Changes")
                    }
                }
                .buttonStyle(FeatureActionButtonStyle(kind: .primary))
                .disabled(saving || confirmKeyInput != item.key || typedReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("catalog-save-\(item.key)")

                Button("Cancel") {
                    cancelEditing()
                }
                .buttonStyle(FeatureActionButtonStyle(kind: .secondary, fillsWidth: false))
                .disabled(saving)
                .accessibilityIdentifier("catalog-cancel-\(item.key)")
            }
        }
    }

    private func startEditing(_ item: FeatureCatalogItem) {
        if saving { return }
        editingKey = item.key
        selectedDefault = item.default_enabled
        selectedMode = item.enforcement_mode
        typedReason = ""
        confirmKeyInput = ""
        editError = nil
        notice = nil
    }

    private func cancelEditing() {
        editingKey = nil
        typedReason = ""
        confirmKeyInput = ""
        editError = nil
    }

    private func loadCatalog() async {
        loading = true
        error = nil
        do {
            items = try await AdminAPI.featureCatalog()
        } catch {
            self.error = FeatureErrorMapper.map(error)
        }
        loading = false
    }

    private func saveCatalogItem(_ item: FeatureCatalogItem) async {
        guard confirmKeyInput == item.key else {
            editError = "Type \"\(item.key)\" exactly to confirm."
            return
        }

        let validation = FeatureValidation.validateReason(typedReason)
        guard case .success(let trimmedReason) = validation else {
            if case .failure(let valErr) = validation {
                editError = valErr.localizedDescription
            }
            return
        }

        saving = true
        editError = nil
        notice = nil

        do {
            try await AdminAPI.setFeatureCatalog(
                featureKey: item.key,
                defaultEnabled: selectedDefault,
                enforcementMode: selectedMode,
                reason: trimmedReason
            )
            notice = "Updated global catalog for \(item.label)."
            cancelEditing()
            await loadCatalog()
        } catch {
            editError = FeatureErrorMapper.map(error)
        }
        saving = false
    }
}
