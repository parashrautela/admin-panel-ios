import SwiftUI

// Mirrors the web WholesalerReview screen.
struct WholesalerReviewView: View {
    let entity: ReviewEntity
    let submissionId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toast: ToastCenter

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

    // MARK: - Main layout

    private func content(_ submission: Submission) -> some View {
        ScrollView {
            HStack(alignment: .top, spacing: 40) {
                leftColumn(submission)
                    .frame(maxWidth: .infinity, alignment: .leading)
                actionsPanel(submission)
                    .frame(width: 300)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity)
        }
    }

    private func leftColumn(_ submission: Submission) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 12) {
                Text(submission.displayName)
                    .font(.system(size: 30, weight: .light))
                    .foregroundColor(.gray900)
                HStack(spacing: 12) {
                    Text(submission.submittedDateText)
                    Text("•")
                    Text(submission.id)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 150, alignment: .leading)
                    StatusBadge(status: submission.status)
                }
                .font(.system(size: 14))
                .foregroundColor(.gray600)
            }
            .padding(.bottom, 40)

            personalDetails(submission)
                .padding(.bottom, 24)
            businessDetails(submission)
                .padding(.bottom, 24)
            verificationDocuments(submission)
        }
    }

    // MARK: - Detail cards

    private func personalDetails(_ submission: Submission) -> some View {
        sectionCard("Personal Details") {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 24) {
                        infoField("FULL NAME", submission.displayName)
                        infoField("AADHAAR NUMBER", submission.aadhar_number ?? "N/A")
                    }
                    infoField("SUBMITTED", submission.submittedDateTimeText)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray50)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(alignment: .top, spacing: 20) {
                    DocumentCard(url: submission.aadhaar_front_url, label: "Aadhaar Front")
                    DocumentCard(url: submission.aadhaar_back_url, label: "Aadhaar Back")
                }
            }
        }
    }

    private func businessDetails(_ submission: Submission) -> some View {
        sectionCard("Business Details") {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 24) {
                        infoField("BUSINESS NAME", submission.business_name ?? "—")
                        infoField("STATE", submission.state ?? "—")
                    }
                    infoField("CITY", submission.city ?? "—")
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray50)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 12) {
                    Text("BUSINESS LOGO")
                        .font(.system(size: 12, weight: .medium))
                        .kerning(0.6)
                        .foregroundColor(.gray500)

                    if let logoURL = submission.business_logo_url, let url = URL(string: logoURL) {
                        VStack(alignment: .leading, spacing: 12) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.gray100
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.gray200, lineWidth: 1))

                            Link(destination: url) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("View full size")
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.black)
                            }
                        }
                    } else {
                        Circle()
                            .fill(Color.gray900)
                            .frame(width: 64, height: 64)
                            .overlay(
                                Text(submission.initial)
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white)
                            )
                    }
                }
            }
        }
    }

    private func verificationDocuments(_ submission: Submission) -> some View {
        sectionCard("Verification Documents") {
            HStack(alignment: .top, spacing: 20) {
                DocumentCard(url: submission.pan_card_url, label: "PAN Card")
                DocumentCard(url: submission.gst_certificate_url, label: "GST Certificate")
            }
        }
    }

    private func sectionCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.gray900)
            content()
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray200.opacity(0.6), lineWidth: 1)
        )
    }

    private func infoField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .kerning(0.6)
                .foregroundColor(.gray500)
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.gray900)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Document card

struct DocumentCard: View {
    let url: String?
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray900)

            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Color.gray100
                    if let url, let imageURL = URL(string: url) {
                        AsyncImage(url: imageURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                    } else {
                        Text("Not provided")
                            .font(.system(size: 14))
                            .foregroundColor(.gray400)
                    }
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text("\(label).jpg")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray900)
                    .lineLimit(1)

                if let url, let linkURL = URL(string: url) {
                    Link(destination: linkURL) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .medium))
                            Text("View full size")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black)
                    }
                }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray200, lineWidth: 1)
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray50)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray100, lineWidth: 1)
        )
    }
}
