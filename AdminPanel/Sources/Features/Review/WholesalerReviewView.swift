import SwiftUI
import UIKit

// Mirrors the web WholesalerReview screen, with the documents laid out for a
// touch screen: every file is shown whole and opens full screen in the app.
struct WholesalerReviewView: View {
    let entity: ReviewEntity
    let submissionId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var toast: ToastCenter
    private var isCompact: Bool { horizontalSizeClass == .compact }

    @State private var submission: Submission?
    @State private var loading = true
    @State private var loadFailed = false

    @State private var showResubmission = false
    @State private var showRejection = false
    @State private var showBanModal = false
    @State private var selectedDocuments: [String] = []
    @State private var resubmissionReason = ""
    @State private var rejectionReason = ""
    @State private var rejectionNotes = ""
    @State private var adminNotes = ""
    @State private var actionLoading = false
    @State private var viewerRequest: DocumentViewerRequest?

    private let resubmissionDocs = ["Aadhaar Front", "Aadhaar Back", "PAN Card", "GST Certificate"]
    private let rejectionReasons = [
        "Documents appear fraudulent or tampered",
        "Business does not exist or unverifiable",
        "Aadhaar details do not match business name",
        "GST number is invalid or expired",
        "PAN card does not match submitted details",
        "Incomplete submission — missing documents",
        "Duplicate account detected",
        "Other (specify below)"
    ]

    var body: some View {
        ZStack {
            LiquidBackground()

            Group {
                if loading {
                    centerMessage("Loading \(entity.label) data...", color: .gray500)
                } else if let submission {
                    content(submission)
                } else {
                    centerMessage("\(entity.label) not found", color: .red500)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            do {
                let data = try await AdminAPI.fetchSubmissionDetail(entity: entity, id: submissionId)
                submission = data
                adminNotes = data.admin_notes ?? ""
            } catch {
                loadFailed = true
                toast.show("Failed to load \(entity.label.lowercased()) details", isError: true)
            }
            loading = false
        }
        .fullScreenCover(item: $viewerRequest) { request in
            DocumentViewer(documents: request.documents, startIndex: request.startIndex)
        }
        .overlay {
            if showBanModal, let submission {
                banModal(submission)
            }
        }
    }

    private func centerMessage(_ text: String, color: Color) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(color)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Documents

    /// The four files an admin is here to check, in the order they're asked
    /// for during onboarding. The business logo is deliberately not one of
    /// them — it's branding, not evidence, so it sits in the header instead.
    private func documents(_ submission: Submission) -> [ReviewDocument] {
        [
            ReviewDocument(label: "Aadhaar Front", urlString: submission.aadhaar_front_url),
            ReviewDocument(label: "Aadhaar Back", urlString: submission.aadhaar_back_url),
            ReviewDocument(label: "PAN Card", urlString: submission.pan_card_url),
            ReviewDocument(label: "GST Certificate", urlString: submission.gst_certificate_url),
        ]
    }

    /// Opens the viewer on one document, with every other provided document
    /// swipeable from it — an admin comparing the two sides of an Aadhaar card
    /// shouldn't have to close and reopen.
    private func openViewer(_ document: ReviewDocument, in all: [ReviewDocument]) {
        let provided = all.filter(\.isProvided)
        let index = provided.firstIndex(of: document) ?? 0
        viewerRequest = DocumentViewerRequest(documents: provided, startIndex: index)
    }

    // MARK: - Main layout

    private func content(_ submission: Submission) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isCompact ? 20 : 24) {
                backButton
                header(submission)
                BusinessCreditsAndReferrals(entity: entity, submission: submission)

                // A fixed 320pt actions panel beside the review content
                // doesn't leave enough room for either on phone width —
                // stack them instead, actions below so the documents being
                // reviewed stay the first thing on screen.
                if isCompact {
                    reviewColumn(submission)
                    actionsPanel(submission)
                } else {
                    HStack(alignment: .top, spacing: 32) {
                        reviewColumn(submission)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        actionsPanel(submission)
                            .frame(width: 320)
                    }
                }
            }
            .padding(.horizontal, isCompact ? 16 : 32)
            .padding(.vertical, isCompact ? 20 : 40)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity)
        }
    }

    /// Claimed details first, documents directly under them: the review is a
    /// comparison of the two, so they belong within a scroll of each other.
    private func reviewColumn(_ submission: Submission) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 20 : 24) {
            detailsCard(submission)
            documentsCard(submission)
            historyCard(submission)
        }
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 14, weight: .medium))
                Text("Back")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(.black)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header

    private func header(_ submission: Submission) -> some View {
        let logo = ReviewDocument(label: "Business Logo", urlString: submission.business_logo_url)

        return HStack(alignment: .top, spacing: 16) {
            logoAvatar(submission, logo: logo)

            VStack(alignment: .leading, spacing: 10) {
                // The status is the first thing to know about a submission, so
                // it rides beside the name rather than at the end of a metadata
                // line where it used to get lost.
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(submission.displayName)
                        .font(.system(size: isCompact ? 26 : 30, weight: .light))
                        .foregroundColor(.gray900)
                    StatusBadge(status: submission.status)
                }

                // The date and the id chip together overflow phone width and
                // wrap into a ragged two-line clump — stack them there.
                let submitted = Text("Submitted \(submission.submittedDateTimeText)")
                    .font(.system(size: 14))
                    .foregroundColor(.gray600)

                if isCompact {
                    VStack(alignment: .leading, spacing: 8) {
                        submitted
                        idChip(submission)
                    }
                } else {
                    HStack(spacing: 10) {
                        submitted
                        idChip(submission)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func logoAvatar(_ submission: Submission, logo: ReviewDocument) -> some View {
        let size: CGFloat = isCompact ? 52 : 64

        if logo.isProvided {
            Button {
                openViewer(logo, in: [logo])
            } label: {
                DocumentPreview(document: logo)
                    .frame(width: size, height: size)
                    .background(Color.gray100)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.gray200, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View business logo")
        } else {
            Circle()
                .fill(Color.gray900)
                .frame(width: size, height: size)
                .overlay(
                    Text(submission.initial)
                        .font(.system(size: size / 3, weight: .medium))
                        .foregroundColor(.white)
                )
        }
    }

    private func idChip(_ submission: Submission) -> some View {
        Button {
            copy(submission.id, named: "Submission ID")
        } label: {
            HStack(spacing: 6) {
                Text(submission.id)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 140, alignment: .leading)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.gray600)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.gray100, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy submission ID")
    }

    // MARK: - Details

    private struct DetailField: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        var copyable = false
        var monospaced = false
    }

    private func detailFields(_ submission: Submission) -> [DetailField] {
        var fields: [DetailField] = [
            // Grouped into fours and monospaced so it can be read straight off
            // the screen against the Aadhaar card below it.
            DetailField(
                label: "AADHAAR NUMBER",
                value: Self.groupedAadhaar(submission.aadhar_number),
                copyable: submission.aadhar_number?.isEmpty == false,
                monospaced: true
            ),
            DetailField(label: "BUSINESS NAME", value: submission.business_name.presentable),
            DetailField(label: "CITY", value: submission.city.presentable),
            DetailField(label: "STATE", value: submission.state.presentable),
        ]
        // Referrals are only set for some submissions; an empty labelled box
        // for everyone else is noise.
        if let referredBy = submission.referred_by, !referredBy.isEmpty {
            fields.append(DetailField(label: "INVITED BY", value: submission.inviter_business_name ?? referredBy))
        }
        if let code = submission.referral_code, !code.isEmpty {
            fields.append(DetailField(label: "REFERRAL CODE", value: code, copyable: true, monospaced: true))
        }
        return fields
    }

    private func detailsCard(_ submission: Submission) -> some View {
        sectionCard("Applicant details") {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 20, alignment: .topLeading),
                    count: isCompact ? 1 : 2
                ),
                alignment: .leading,
                spacing: 20
            ) {
                ForEach(detailFields(submission)) { field in
                    detailField(field)
                }
            }
        }
    }

    private func detailField(_ field: DetailField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.label)
                .font(.system(size: 12, weight: .medium))
                .kerning(0.6)
                .foregroundColor(.gray500)

            HStack(spacing: 8) {
                Text(field.value)
                    .font(.system(size: 15, weight: .medium, design: field.monospaced ? .monospaced : .default))
                    .foregroundColor(.gray900)
                    .textSelection(.enabled)

                if field.copyable {
                    Button {
                        copy(field.value, named: field.label.capitalized)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray500)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy \(field.label.lowercased())")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `583485235823` is a wall of digits to check by eye; `5834 8523 5823`
    /// matches how the number is printed on the card itself.
    private static func groupedAadhaar(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let digits = raw.filter(\.isNumber)
        guard digits.count == 12 else { return raw }
        return stride(from: 0, to: digits.count, by: 4)
            .map { offset -> String in
                let start = digits.index(digits.startIndex, offsetBy: offset)
                let end = digits.index(start, offsetBy: 4)
                return String(digits[start..<end])
            }
            .joined(separator: " ")
    }

    // MARK: - Documents

    private func documentsCard(_ submission: Submission) -> some View {
        let all = documents(submission)
        let providedCount = all.filter(\.isProvided).count

        // Amber, not red: a document that was never uploaded is something to
        // ask for, which is what the resubmission action is there for — it
        // isn't a failure the way a rejected application is.
        let complete = providedCount == all.count

        return sectionCard("Documents", accessory: {
            Text("\(providedCount) of \(all.count) provided")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(complete ? .gray600 : .yellow900)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(complete ? Color.gray100 : Color.yellow100, in: Capsule())
        }) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tap a document to open it full screen — pinch or double-tap to zoom, swipe for the next one.")
                    .font(.system(size: 13))
                    .foregroundColor(.gray500)
                    .fixedSize(horizontal: false, vertical: true)

                // Adaptive rather than a fixed column count: beside a 320pt
                // actions panel, two columns on an 11" iPad leave each
                // document ~170pt across — narrower than the single column a
                // phone gives it, which is the wrong way round. This fits as
                // many readable columns as there is room for, and one wide one
                // when there isn't.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240), spacing: 16, alignment: .top)],
                    spacing: 20
                ) {
                    ForEach(all) { document in
                        DocumentTile(document: document) {
                            openViewer(document, in: all)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Earlier decision

    /// A resubmission or rejection is already recorded on the row, but the app
    /// never showed it — so an admin picking a submission back up couldn't see
    /// what was asked for last time.
    @ViewBuilder
    private func historyCard(_ submission: Submission) -> some View {
        let reason = (submission.rejection_reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let requested = submission.rejected_documents ?? []

        if !reason.isEmpty || !requested.isEmpty {
            sectionCard(submission.status == .resubmission_required ? "Resubmission requested" : "Earlier decision") {
                VStack(alignment: .leading, spacing: 16) {
                    if !requested.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DOCUMENTS ASKED FOR")
                                .font(.system(size: 12, weight: .medium))
                                .kerning(0.6)
                                .foregroundColor(.gray500)
                            FlowChips(items: requested)
                        }
                    }
                    if !reason.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("REASON GIVEN")
                                .font(.system(size: 12, weight: .medium))
                                .kerning(0.6)
                                .foregroundColor(.gray500)
                            Text(reason)
                                .font(.system(size: 14))
                                .foregroundColor(.gray900)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Card chrome

    private func sectionCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        sectionCard(title, accessory: { EmptyView() }, content: content)
    }

    private func sectionCard<Accessory: View, Content: View>(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.gray900)
                Spacer(minLength: 0)
                accessory()
            }
            content()
        }
        .padding(isCompact ? 20 : 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray200.opacity(0.6), lineWidth: 1)
        )
    }

    private func copy(_ value: String, named name: String) {
        UIPasteboard.general.string = value
        toast.show("\(name) copied")
    }

    // MARK: - Actions panel

    private func actionsPanel(_ submission: Submission) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Actions")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.gray900)
                .padding(.bottom, 8)
            Text("Review all documents before taking action")
                .font(.system(size: 14))
                .foregroundColor(.gray500)
                .padding(.bottom, 32)

            VStack(alignment: .leading, spacing: 12) {
                actionBlock(caption: "\(entity.label) gets immediate access") {
                    primaryButton("Verify & Approve", icon: "checkmark") {
                        run { try await AdminAPI.verifySubmission(entity: entity, id: submission.id) }
                    }
                }

                actionBlock(caption: "Flag for further review") {
                    outlineButton("Put On Hold", icon: "pause") {
                        run { try await AdminAPI.putOnHold(entity: entity, id: submission.id, notes: adminNotes) }
                    }
                }

                actionBlock(caption: "Request specific documents") {
                    outlineButton("Request Resubmission", icon: "arrow.counterclockwise") {
                        withAnimation { showResubmission.toggle() }
                    }
                }

                if showResubmission {
                    resubmissionPanel(submission)
                }

                Divider().overlay(Color.gray200).padding(.vertical, 20)

                outlineButton("Reject Application", icon: "xmark", borderColor: .gray900) {
                    withAnimation { showRejection.toggle() }
                }

                if showRejection {
                    rejectionPanel(submission)
                }

                Button {
                    showBanModal = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "nosign")
                            .font(.system(size: 13, weight: .medium))
                        Text("Ban Permanently")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray900)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

                notesSection(submission)
                    .padding(.top, 32)
            }
            .disabled(actionLoading)
            .opacity(actionLoading ? 0.6 : 1)
        }
        .padding(24)
        .glassEffect(.regular.tint(.white.opacity(0.35)), in: RoundedRectangle(cornerRadius: 20))
    }

    private func actionBlock(caption: String, @ViewBuilder button: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            button()
            Text(caption)
                .font(.system(size: 12))
                .foregroundColor(.gray500)
                .padding(.horizontal, 4)
        }
    }

    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(.black)
    }

    private func outlineButton(
        _ title: String,
        icon: String,
        borderColor: Color = .gray300,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                Text(title)
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(.gray900)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
    }

    private func resubmissionPanel(_ submission: Submission) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select documents to resubmit:")
                .font(.system(size: 14, weight: .medium))

            VStack(alignment: .leading, spacing: 10) {
                ForEach(resubmissionDocs, id: \.self) { doc in
                    Button {
                        if selectedDocuments.contains(doc) {
                            selectedDocuments.removeAll { $0 == doc }
                        } else {
                            selectedDocuments.append(doc)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedDocuments.contains(doc) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 17))
                                .foregroundColor(selectedDocuments.contains(doc) ? .black : .gray400)
                            Text(doc)
                                .font(.system(size: 14))
                                .foregroundColor(.gray900)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Reason (required)")
                    .font(.system(size: 14, weight: .medium))
                textArea($resubmissionReason, placeholder: "Explain what needs to be corrected...", height: 84)
            }

            Button {
                run {
                    try await AdminAPI.requestResubmission(
                        entity: entity,
                        id: submission.id,
                        documents: selectedDocuments,
                        reason: resubmissionReason
                    )
                }
            } label: {
                Text("Send Request")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(.black)
            .disabled(resubmissionReason.isEmpty || selectedDocuments.isEmpty)
            .opacity(resubmissionReason.isEmpty || selectedDocuments.isEmpty ? 0.5 : 1)
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray200.opacity(0.6), lineWidth: 1)
        )
    }

    private func rejectionPanel(_ submission: Submission) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if entity == .retailer {
                Text("Final rejection ends any new invitation gift and releases its funding. Use Request Resubmission when documents need corrections.")
                    .font(.system(size: 13)).foregroundColor(.gray600)
            }
            Text("Select rejection reason:")
                .font(.system(size: 14, weight: .medium))

            VStack(alignment: .leading, spacing: 10) {
                ForEach(rejectionReasons, id: \.self) { reason in
                    Button {
                        rejectionReason = reason
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: rejectionReason == reason ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 16))
                                .foregroundColor(rejectionReason == reason ? .black : .gray400)
                                .padding(.top, 1)
                            Text(reason)
                                .font(.system(size: 14))
                                .foregroundColor(.gray900)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Additional notes (optional)")
                    .font(.system(size: 14, weight: .medium))
                textArea($rejectionNotes, placeholder: "Add context...", height: 84)
            }

            Button {
                let fullReason = rejectionReason + (rejectionNotes.isEmpty ? "" : " - \(rejectionNotes)")
                run { try await AdminAPI.rejectSubmission(entity: entity, id: submission.id, reason: fullReason) }
            } label: {
                Text("Confirm Rejection")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(.black)
            .disabled(rejectionReason.isEmpty)
            .opacity(rejectionReason.isEmpty ? 0.5 : 1)
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray200.opacity(0.6), lineWidth: 1)
        )
    }

    private func notesSection(_ submission: Submission) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().overlay(Color.gray200)
            Text("Internal notes")
                .font(.system(size: 14, weight: .medium))
                .padding(.top, 12)
            textArea(
                $adminNotes,
                placeholder: "Add notes (not visible to \(entity.label.lowercased()))...",
                height: 104,
                background: .gray50
            )
            Button {
                actionLoading = true
                Task {
                    do {
                        try await AdminAPI.saveNotes(entity: entity, id: submission.id, notes: adminNotes)
                        toast.show("Notes saved")
                    } catch {
                        toast.show("Failed to save notes", isError: true)
                    }
                    actionLoading = false
                }
            } label: {
                Text("Save note")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.black)
            }
            .buttonStyle(.plain)
        }
    }

    private func textArea(
        _ text: Binding<String>,
        placeholder: String,
        height: CGFloat,
        background: Color = .white
    ) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(height: height)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray300, lineWidth: 1)
                )
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 14))
                    .foregroundColor(.gray400)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Ban modal

    private func banModal(_ submission: Submission) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { showBanModal = false }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    Circle()
                        .fill(Color.gray100)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 22))
                                .foregroundColor(.gray900)
                        )
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Are you sure?")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.gray900)
                        Text("This will permanently ban \(submission.displayName) from the platform. This action cannot be undone.")
                            .font(.system(size: 14))
                            .foregroundColor(.gray600)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 32)

                HStack(spacing: 12) {
                    Button {
                        showBanModal = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.gray900)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)

                    Button {
                        showBanModal = false
                        run { try await AdminAPI.banSubmission(entity: entity, id: submission.id) }
                    } label: {
                        Text("Yes, Ban User")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.black)
                    .disabled(actionLoading)
                }
            }
            .padding(32)
            .glassEffect(.regular.tint(.white.opacity(0.5)), in: RoundedRectangle(cornerRadius: 20))
            .frame(maxWidth: 448)
            .padding(16)
        }
    }

    // MARK: - Action runner (mirrors the web wrapAction)

    private func run(_ action: @escaping () async throws -> Void) {
        actionLoading = true
        Task {
            do {
                try await action()
                toast.show("Status updated successfully")
                dismiss()
            } catch {
                toast.show(error.localizedDescription, isError: true)
            }
            actionLoading = false
        }
    }
}

// MARK: - Document tile

/// One document in the review grid: the whole file on a neutral backdrop, its
/// real type beside the label, and a tap target covering the lot.
///
/// The preview is fitted, not filled. A filled 160pt strip — what this used to
/// be — centre-crops an ID card to the part with the least information on it,
/// which is the opposite of what the screen is for.
struct DocumentTile: View {
    let document: ReviewDocument
    let onOpen: () -> Void

    @State private var kind: String?

    var body: some View {
        // The label leads the preview rather than following it: under a fitted
        // image the caption floats halfway to the next tile, and in a
        // single-column grid it reads as that tile's heading instead.
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // One line, always: a wrapped label is taller than its
                // neighbours' and pushes that tile's preview out of line with
                // the rest of the row.
                Text(document.label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(document.isProvided ? .gray900 : .gray500)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                badge
            }

            if document.isProvided {
                Button(action: onOpen) {
                    preview
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(document.label), open full screen")
            } else {
                missing
            }
        }
    }

    /// A flexible colour is what gives the box its 4:3 shape — a stack of
    /// fixed-size content has an ideal size of its own, and `aspectRatio` then
    /// fits the ratio inside *that* instead of the column width.
    private func box(_ fill: Color, @ViewBuilder content: () -> some View) -> some View {
        fill
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay { content() }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var preview: some View {
        box(.gray100) {
            DocumentPreview(document: document) { kind = $0.kindLabel }
                .padding(6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray200, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(7)
                .background(.black.opacity(0.45), in: Circle())
                .padding(8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private var missing: some View {
        box(.gray50) {
            VStack(spacing: 8) {
                Image(systemName: "doc")
                    .font(.system(size: 22))
                Text("Not provided")
                    .font(.system(size: 13))
            }
            .foregroundColor(.gray400)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray300, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        )
    }

    @ViewBuilder
    private var badge: some View {
        if !document.isProvided {
            chip("Missing", background: .yellow100, foreground: .yellow900)
        } else if let kind {
            chip(kind, background: .gray100, foreground: .gray600)
        }
    }

    private func chip(_ text: String, background: Color, foreground: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(foreground)
            // The label next to it claims the row's width first, which leaves
            // the chip narrow enough to wrap "Missing" mid-word.
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
    }
}

// MARK: - Small helpers

/// Wraps chips onto as many lines as they need — the documents asked for in a
/// resubmission are four labels of unequal length, which an HStack would push
/// off the edge of a phone.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray700)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.gray100, in: Capsule())
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, in: width)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, in: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

private extension Optional where Wrapped == String {
    /// Blank columns come back as "" as often as NULL; both read as "—".
    var presentable: String {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return "—" }
        return value
    }
}
