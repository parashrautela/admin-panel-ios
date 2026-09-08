import SwiftUI

struct WholesalerReviewView: View {
    let entity: ReviewEntity
    let submissionId: String
    @EnvironmentObject private var auth: AdminAuth
    @Environment(\.scenePhase) private var scene
    @State private var detail: ReviewDetail?
    @State private var error: AdminAPIError?
    @State private var busy = false
    @State private var noteText = ""
    @State private var noteID = UUID().uuidString
    @State private var noteBusy = false
    @State private var noteError: AdminAPIError?
    @State private var actionError: AdminAPIError?
    @State private var revealed: String?
    @State private var viewing: EvidenceDocument?
    @State private var inspected: Set<String> = []
    @State private var assessments: [String: String] = [:]
    @State private var decisionOpen = false
    @State private var confirmBanOpen = false
    @State private var confirmationReason = ""
    @State private var banCommand = UUID().uuidString
    @State private var receipt: DecisionReceipt?
    @State private var accountActionBusy = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error { ErrorPanel(error: error) { Task { await load() } } }
                if busy { ProgressView("Loading application…") }
                if let detail {
                    header(detail.submission)
                    if let actionError { ErrorPanel(error: actionError, retry: nil) }
                    if let request = detail.ban_request {
                        Panel(title: "Ban request awaiting review", symbol: "person.2.badge.key") {
                            Text(request.reason)
                            Text("A different supervisor must approve this request.").font(.footnote).foregroundStyle(.secondary)
                            if auth.profile?.isSupervisor == true && auth.profile?.id != request.requested_by {
                                Button("Review ban request", role: .destructive) { confirmBanOpen = true }.frame(minHeight: 44)
                            }
                        }
                    }
                    identity(detail.submission)
                    Panel(title: "Evidence", symbol: "doc.text.viewfinder") {
                        Text("Open each file, inspect it, and record an assessment. All four documents must pass before approval.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        ForEach(detail.documents) { document in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    Image(systemName: document.available ? "doc.richtext" : "doc.badge.ellipsis").foregroundStyle(AdminTheme.accent).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(document.title).font(.headline)
                                        Text(document.available ? document.filename : "Document not supplied").font(.caption).foregroundStyle(.secondary)
                                        if let revision = document.revision { Text("Revision " + revision).font(.caption2).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    if inspected.contains(document.kind) { Image(systemName: "checkmark.circle").foregroundStyle(.green).accessibilityLabel("Opened for inspection") }
                                }
                                Button { viewing = document } label: {
                                    Label(document.available ? "Inspect document" : "Document unavailable", systemImage: "viewfinder").frame(minHeight: 44)
                                }.buttonStyle(.bordered).disabled(!document.available || error != nil)
                                    .accessibilityIdentifier("inspect-" + document.kind)
                                if auth.profile?.canReview == true {
                                    Picker("Assessment for " + document.title, selection: assessmentBinding(document.kind)) {
                                        Text("Not assessed").tag("")
                                        Text("Pass").tag("pass")
                                        Text("Needs replacement").tag("resubmit")
                                        Text("Suspected tampering").tag("suspected")
                                    }.pickerStyle(.menu).disabled(!inspected.contains(document.kind)).frame(minHeight: 44)
                                }
                            }
                            if document.id != detail.documents.last?.id { Divider() }
                        }
                    }
                    notesAndActivity(detail)
                } else if !busy && error == nil {
                    ContentUnavailableView("Select an application", systemImage: "doc.text.magnifyingglass")
                }
            }.padding(20).frame(maxWidth: 1080).frame(maxWidth: .infinity)
        }
        .background(AdminTheme.background).navigationTitle("Application review")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let detail {
                HStack(spacing: 12) {
                    StatusBadge(status: detail.submission.status)
                    Spacer(minLength: 4)
                    Button { decisionOpen = true } label: {
                        Label("Review decision", systemImage: "checklist").frame(minHeight: 44)
                    }.buttonStyle(.borderedProminent)
                        .disabled(!detail.submission.status.actionable || auth.profile?.canReview != true || error != nil || busy)
                        .accessibilityIdentifier("reviewDecision")
                }.padding(12).background(.regularMaterial)
            }
        }
        .toolbar {
            Button { Task { await load() } } label: { Label("Refresh application", systemImage: "arrow.clockwise") }.keyboardShortcut("r", modifiers: .command)
        }
        .task { await load() }
        .refreshable { await load() }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: scene) { if scene != .active { revealed = nil } }
        .sheet(item: $viewing) { document in
            EvidenceViewer(entity: entity, submissionID: submissionId, initial: document, documents: detail?.documents ?? []) { kind in inspected.insert(kind) }
        }
        .sheet(isPresented: $decisionOpen) {
            if let detail {
                DecisionSheet(entity: entity, detail: detail, assessments: assessments) {
                    Task { await load(); NotificationCenter.default.post(name: .adminDataChanged, object: nil) }
                }
            }
        }
        .sheet(isPresented: $confirmBanOpen) {
            NavigationStack {
                Form {
                    Text("Confirm permanent ban").font(.title2.bold())
                    Text("This will block the account. Your confirmation is recorded separately from the requesting supervisor.")
                    TextField("Independent review reason", text: $confirmationReason, axis: .vertical).lineLimit(3...8)
                    if let actionError { ErrorPanel(error: actionError, retry: nil) }
                    Button("Confirm permanent ban", role: .destructive) { Task { await confirmBan() } }
                        .disabled(confirmationReason.trimmed.count < 5 || accountActionBusy)
                    if accountActionBusy { ProgressView("Recording confirmation…") }
                }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { confirmBanOpen = false }.disabled(accountActionBusy) } }
            }.interactiveDismissDisabled(accountActionBusy)
        }
        .sheet(item: $receipt) { value in ReceiptView(receipt: value) { receipt = nil } }
    }
    @ViewBuilder private func header(_ submission: Submission) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EnvironmentBadge()
            Text(submission.business).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text(submission.displayName + " · " + entity.label).font(.title3).foregroundStyle(.secondary)
            Text(submission.submittedDateTimeText).font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(submission.id).font(.caption.monospaced()).textSelection(.enabled)
                Button {
                    UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: submission.id]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
                    UIAccessibility.post(notification: .announcement, argument: "Application ID copied")
                } label: { Image(systemName: "doc.on.doc").frame(width: 44, height: 44) }.accessibilityLabel("Copy application ID")
            }
            if auth.profile?.canReview == true {
                let mine = submission.assigned_to == auth.profile?.id
                Button { Task { await assign(!mine) } } label: {
                    Label(mine ? "Release my assignment" : "Assign to me", systemImage: "person.crop.circle.badge.checkmark").frame(minHeight: 44)
                }.buttonStyle(.bordered)
                    .disabled(accountActionBusy || error != nil || (submission.assigned_to != nil && !mine && auth.profile?.isSupervisor != true))
                if submission.assigned_to != nil && !mine { Text("Assigned to another reviewer").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private func identity(_ submission: Submission) -> some View {
        Panel(title: "Applicant and business", symbol: "person.text.rectangle") {
            LabeledContent("Applicant", value: submission.displayName)
            LabeledContent("Business", value: submission.business)
            LabeledContent("Location", value: submission.location)
            LabeledContent("Email", value: submission.email?.nonblank ?? "Not provided")
            LabeledContent("Phone", value: submission.phone?.nonblank ?? "Not provided")
            VStack(alignment: .leading, spacing: 8) {
                Text("Aadhaar").font(.subheadline.weight(.semibold))
                Text(revealed ?? submission.maskedAadhaar).font(.body.monospaced()).privacySensitive()
                if auth.profile?.can_reveal_pii == true {
                    Button(revealed == nil ? "Reveal for review" : "Hide Aadhaar") {
                        if revealed != nil { revealed = nil }
                        else { Task { await reveal() } }
                    }.frame(minHeight: 44).disabled(accountActionBusy)
                    Text("Reveals are recorded against your administrator account.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let reason = submission.rejection_reason?.nonblank { LabeledContent("Previous reason", value: reason) }
        }
    }
    private func notesAndActivity(_ detail: ReviewDetail) -> some View {
        Panel(title: "Notes and activity", symbol: "clock.arrow.circlepath") {
            if let oldNotes = detail.submission.admin_notes?.nonblank {
                Text("Legacy note · author unavailable").font(.caption.weight(.semibold))
                Text(oldNotes).font(.subheadline)
                Divider()
            }
            if auth.profile?.canReview == true {
                TextField("Add an internal note", text: $noteText, axis: .vertical).lineLimit(3...8).textFieldStyle(.roundedBorder).accessibilityIdentifier("internalNote")
                Text("Internal only. Notes are added to history and cannot overwrite earlier notes.").font(.caption).foregroundStyle(.secondary)
                if let noteError { ErrorPanel(error: noteError, retry: nil) }
                Button { Task { await saveNote() } } label: {
                    HStack { if noteBusy { ProgressView() }; Text("Add note") }.frame(minHeight: 44)
                }.buttonStyle(.bordered).disabled(noteBusy || noteText.trimmed.isEmpty || noteText.count > 2000).accessibilityIdentifier("addNote")
            }
            if detail.events.isEmpty { Text("No recorded activity yet.").foregroundStyle(.secondary) }
            ForEach(detail.events) { event in
                VStack(alignment: .leading, spacing: 5) {
                    Label(event.event_type.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: event.event_type == "note" ? "text.bubble" : "clock")
                        .font(.subheadline.weight(.semibold))
                    Text(event.actor_name + " · " + Submission.timeText(event.occurred_at)).font(.caption).foregroundStyle(.secondary)
                    if let reason = event.reason { Text(reason).font(.subheadline) }
                    if let status = event.new_status { Text("Result: " + (WholesalerStatus(rawValue: status)?.label ?? status)).font(.caption) }
                }.accessibilityElement(children: .combine)
                Divider()
            }
        }
    }
    private func assessmentBinding(_ kind: String) -> Binding<String> { Binding(get: { assessments[kind] ?? "" }, set: { assessments[kind] = $0 }) }
    private func load() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let value = try await AdminAPI.shared.detail(entity: entity, id: submissionId)
            if detail?.submission.version != value.submission.version { inspected = []; assessments = [:] }
            detail = value
        } catch { self.error = AdminAPIError.map(error) }
    }
    private func saveNote() async {
        guard !noteBusy, let value = noteText.nonblank else { return }
        noteBusy = true; noteError = nil
        defer { noteBusy = false }
        do {
            let result = try await AdminAPI.shared.note(entity: entity, id: submissionId, text: value, requestID: noteID)
            noteText = ""; noteID = UUID().uuidString
            UIAccessibility.post(notification: .announcement, argument: result.message)
            await load()
        } catch { noteError = AdminAPIError.map(error) }
    }
    private func assign(_ mine: Bool) async {
        guard let detail, !accountActionBusy else { return }
        accountActionBusy = true; actionError = nil
        defer { accountActionBusy = false }
        do {
            _ = try await AdminAPI.shared.assign(entity: entity, submission: detail.submission, mine: mine, requestID: UUID().uuidString)
            await load()
            NotificationCenter.default.post(name: .adminDataChanged, object: nil)
        } catch { actionError = AdminAPIError.map(error) }
    }
    private func reveal() async {
        guard !accountActionBusy else { return }
        accountActionBusy = true; actionError = nil
        defer { accountActionBusy = false }
        do { revealed = try await AdminAPI.shared.reveal(entity: entity, id: submissionId) }
        catch { actionError = AdminAPIError.map(error) }
    }
    private func confirmBan() async {
        guard let detail, let request = detail.ban_request, !accountActionBusy else { return }
        accountActionBusy = true; actionError = nil
        defer { accountActionBusy = false }
        do {
            let result = try await AdminAPI.shared.confirmBan(entity: entity, submission: detail.submission, request: request, reason: confirmationReason, requestID: banCommand)
            confirmBanOpen = false; receipt = result; banCommand = UUID().uuidString
            await load(); NotificationCenter.default.post(name: .adminDataChanged, object: nil)
        } catch { actionError = AdminAPIError.map(error) }
    }
}

struct DecisionSheet: View {
    let entity: ReviewEntity
    let detail: ReviewDetail
    let assessments: [String: String]
    let completed: () -> Void
    @EnvironmentObject private var auth: AdminAuth
    @Environment(\.dismiss) private var dismiss
    @State private var draft = DecisionDraft()
    @State private var busy = false
    @State private var error: AdminAPIError?
    @State private var receipt: DecisionReceipt?
    var body: some View {
        NavigationStack {
            if let receipt {
                ReceiptView(receipt: receipt) { completed(); dismiss() }
            } else {
                Form {
                    Section {
                        Text(detail.submission.business).font(.headline)
                        Text("Acting as " + (auth.profile?.display_name ?? "")).font(.subheadline)
                        Picker("Outcome", selection: $draft.outcome) {
                            ForEach(DecisionOutcome.allCases.filter { $0 != .ban || auth.profile?.isSupervisor == true }) { outcome in Text(outcome.title).tag(outcome) }
                        }
                        Text(draft.outcome.impact).font(.subheadline)
                    }
                    Section("Reason recorded in history") {
                        TextField("Explain the decision", text: $draft.reason, axis: .vertical).lineLimit(3...8).accessibilityIdentifier("decisionReason")
                    }
                    if draft.outcome == .resubmit {
                        Section("Documents to replace") {
                            ForEach(detail.documents) { document in
                                Toggle(document.title, isOn: Binding(get: { draft.documents.contains(document.kind) }, set: { if $0 { draft.documents.insert(document.kind) } else { draft.documents.remove(document.kind) } }))
                            }
                        }
                    }
                    if draft.outcome == .hold {
                        Section("Follow-up") {
                            DatePicker("Review again", selection: $draft.followUp, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            Text("This application will be assigned to you.").font(.caption)
                        }
                    }
                    if [.approve, .resubmit, .reject].contains(draft.outcome) {
                        Section("Message the applicant will receive") {
                            TextField("Applicant-facing message", text: $draft.message, axis: .vertical).lineLimit(3...8).accessibilityIdentifier("applicantMessage")
                        }
                    }
                    Section {
                        Toggle("I reviewed the evidence and understand this decision", isOn: $draft.confirmed).accessibilityIdentifier("decisionConfirm")
                        if let validation = draft.validation(required: detail.documents, status: detail.submission.status) { Text(validation).font(.footnote).foregroundStyle(.secondary) }
                        if let error { ErrorPanel(error: error, retry: nil) }
                        Button {
                            Task { await commit() }
                        } label: {
                            HStack { if busy { ProgressView() }; Text(busy ? "Recording decision…" : "Confirm decision") }.frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.borderedProminent).tint([.reject, .ban].contains(draft.outcome) ? .red : AdminTheme.accent)
                            .disabled(busy || draft.validation(required: detail.documents, status: detail.submission.status) != nil)
                            .accessibilityIdentifier("commitDecision")
                    }
                }
                .disabled(busy)
                .navigationTitle("Review decision").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
            }
        }
        .interactiveDismissDisabled(busy || receipt != nil)
        .onAppear { draft.assessments = assessments }
        .onChange(of: draft.outcome) {
            draft.confirmed = false; error = nil
            draft.message = ""; draft.requestID = UUID().uuidString
        }
    }
    private func commit() async {
        guard !busy, draft.validation(required: detail.documents, status: detail.submission.status) == nil else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            receipt = try await AdminAPI.shared.decide(entity: entity, submission: detail.submission, draft: draft)
            UIAccessibility.post(notification: .announcement, argument: "Decision recorded")
        } catch { self.error = AdminAPIError.map(error) }
    }
}
struct ReceiptView: View {
    let receipt: DecisionReceipt
    let done: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundStyle(.green).accessibilityHidden(true)
                Text("Decision recorded").font(.largeTitle.bold())
                Text(receipt.message).font(.title3)
                LabeledContent("Previous status", value: WholesalerStatus(rawValue: receipt.previous_status)?.label ?? receipt.previous_status)
                LabeledContent("Resulting status", value: WholesalerStatus(rawValue: receipt.new_status)?.label ?? receipt.new_status)
                Text(Submission.timeText(receipt.committed_at)).font(.subheadline)
                Text("Event reference").font(.headline)
                Text(receipt.event_id).font(.body.monospaced()).textSelection(.enabled)
                Button("Done", action: done).buttonStyle(.borderedProminent).frame(minHeight: 44).accessibilityIdentifier("receiptDone")
            }.padding(28).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }
    }
}
