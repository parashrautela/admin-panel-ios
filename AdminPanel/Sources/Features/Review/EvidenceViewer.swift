import SwiftUI
import PDFKit

struct EvidenceViewer: View {
    let entity: ReviewEntity
    let submissionID: String
    let initial: EvidenceDocument
    let documents: [EvidenceDocument]
    let onInspected: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected = ""
    @State private var compare = false
    @State private var comparison = ""
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 12) {
                    Picker("Document", selection: $selected) {
                        ForEach(documents.filter(\.available)) { Text($0.title).tag($0.kind) }
                    }.pickerStyle(.menu).accessibilityIdentifier("documentPicker")
                    if compare {
                        Picker("Compare with", selection: $comparison) {
                            ForEach(documents.filter { $0.available && $0.kind != selected }) { Text($0.title).tag($0.kind) }
                        }.pickerStyle(.menu)
                    }
                    if compare && geometry.size.width >= 760 {
                        HStack(spacing: 12) { pane(selected); pane(comparison) }
                    } else if compare {
                        VStack(spacing: 12) { pane(selected); pane(comparison) }
                    } else { pane(selected) }
                    Text("Pinch to zoom • Swipe through pages. Evidence stays in memory and is not exported.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                }.padding(12)
            }
            .background(AdminTheme.background)
            .navigationTitle("Secure evidence review").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("closeEvidence") }
                ToolbarItem(placement: .primaryAction) {
                    Button(compare ? "Single file" : "Compare", systemImage: "rectangle.split.2x1") {
                        comparison = documents.first { $0.available && $0.kind != selected }?.kind ?? ""
                        compare.toggle()
                    }.disabled(documents.filter(\.available).count < 2)
                }
            }
        }
        .onAppear { selected = initial.kind }
        .onChange(of: selected) { _, value in
            if comparison == value { comparison = documents.first { $0.available && $0.kind != value }?.kind ?? "" }
        }
    }
    @ViewBuilder private func pane(_ kind: String) -> some View {
        if let document = documents.first(where: { $0.kind == kind }) {
            EvidencePane(entity: entity, submissionID: submissionID, document: document, onInspected: onInspected).id(kind)
        } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
    }
}

struct EvidencePane: View {
    let entity: ReviewEntity
    let submissionID: String
    let document: EvidenceDocument
    let onInspected: (String) -> Void
    @State private var pdf: PDFDocument?
    @State private var error: AdminAPIError?
    @State private var loading = false
    @State private var rotation = 0
    @State private var page = 1
    @State private var pageCount = 0
    @State private var requestGeneration = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(document.title).font(.headline)
            Text(document.filename).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if let uploaded = document.uploaded_at { Text("Uploaded " + Submission.timeText(uploaded)).font(.caption2) }
            ZStack {
                Color(uiColor: .secondarySystemGroupedBackground)
                if let pdf {
                    SecurePDFView(document: pdf, rotation: rotation, page: $page)
                        .accessibilityLabel(document.title + ", page \(page) of \(pageCount)")
                        .accessibilityIdentifier("evidenceContent")
                } else if let error {
                    ScrollView { ErrorPanel(error: error) { Task { await load() } }.padding() }
                } else { ProgressView("Loading secure evidence…") }
            }.clipShape(RoundedRectangle(cornerRadius: 12))
            if pdf != nil {
                HStack {
                    Text("Page \(page) of \(pageCount)").font(.caption).accessibilityIdentifier("pageCount")
                    Spacer()
                    Button("Rotate", systemImage: "rotate.right") { rotation = (rotation + 90) % 360 }.frame(minHeight: 44)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await load() }
            .onDisappear { requestGeneration = UUID(); pdf = nil }
    }
    private func load() async {
        guard !loading else { return }
        let generation = UUID(); requestGeneration = generation
        loading = true; error = nil
        defer { loading = false }
        do {
            let (data, _) = try await AdminAPI.shared.document(entity: entity, id: submissionID, kind: document.kind)
            try Task.checkCancellation()
            let value: PDFDocument
            if data.starts(with: Data("%PDF-".utf8)), let decoded = PDFDocument(data: data), !decoded.isLocked, decoded.pageCount > 0 {
                value = decoded
            } else if let image = UIImage(data: data), image.size.width * image.size.height <= 80_000_000, let imagePage = PDFPage(image: image) {
                value = PDFDocument(); value.insert(imagePage, at: 0)
            } else {
                throw AdminAPIError(code: "document", message: "This file is unsupported, damaged, password-protected, or too large to render safely. Request a readable PDF, JPEG, PNG, or HEIC file.")
            }
            guard generation == requestGeneration else { return }
            pageCount = value.pageCount; page = 1; pdf = value
            onInspected(document.kind)
        } catch is CancellationError { }
        catch { if generation == requestGeneration { self.error = AdminAPIError.map(error) } }
    }
}

private struct SecurePDFView: UIViewRepresentable {
    let document: PDFDocument
    let rotation: Int
    @Binding var page: Int
    func makeCoordinator() -> Coordinator { Coordinator(page: $page) }
    func makeUIView(context: Context) -> PDFView {
        let view = NoCopyPDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemGroupedBackground
        view.document = document
        context.coordinator.view = view
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak coordinator = context.coordinator] _ in coordinator?.changed() }
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        if context.coordinator.rotation != rotation {
            let delta = rotation - context.coordinator.rotation
            for index in 0..<document.pageCount { if let page = document.page(at: index) { page.rotation += delta } }
            context.coordinator.rotation = rotation
            view.layoutDocumentView(); view.autoScales = true
        }
    }
    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
        if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
        view.document = nil
    }
    final class Coordinator {
        var page: Binding<Int>
        var rotation = 0
        weak var view: PDFView?
        var observer: NSObjectProtocol?
        init(page: Binding<Int>) { self.page = page }
        func changed() {
            guard let view, let current = view.currentPage, let document = view.document else { return }
            page.wrappedValue = document.index(for: current) + 1
        }
    }
}
private final class NoCopyPDFView: PDFView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
}
