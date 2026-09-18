import PDFKit
import SwiftUI

// MARK: - Model

/// One file attached to a submission. Both onboarding flows upload the same
/// five: Aadhaar front and back, PAN card, GST certificate, business logo.
/// Photos arrive as compressed JPEGs, but PDFs pass through untouched, so a
/// document is not necessarily an image.
struct ReviewDocument: Identifiable, Hashable {
    /// The label doubles as the id — unique within a submission, and stable
    /// across a reload so the viewer keeps its place.
    var id: String { label }
    let label: String
    let url: URL?

    var isProvided: Bool { url != nil }

    init(label: String, urlString: String?) {
        self.label = label
        // A document that was never uploaded arrives as NULL from one writer
        // and as an empty string from another — both mean "not provided".
        let trimmed = (urlString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        url = trimmed.isEmpty ? nil : URL(string: trimmed)
    }
}

/// What a downloaded document turned out to be.
enum DocumentContent {
    case image(UIImage)
    case pdf(PDFDocument)
}

/// A document that has been downloaded and decoded once.
struct LoadedDocument {
    let content: DocumentContent
    /// The image itself, or the PDF's first page. Rendered at load so a card
    /// redrawing never re-rasterises a page.
    let preview: UIImage?

    /// Short description of the real file type, for the badge on a card. The
    /// stored file name can't answer this: the web uploader named everything
    /// `.jpg` regardless of what the user picked.
    var kindLabel: String {
        switch content {
        case .image:
            return "Image"
        case .pdf(let pdf):
            return pdf.pageCount > 1 ? "PDF · \(pdf.pageCount) pages" : "PDF"
        }
    }

    init(data: Data) throws {
        // Sniff the bytes rather than trusting the extension, for the same
        // reason kindLabel can't trust the file name.
        if data.starts(with: Self.pdfMagic), let pdf = PDFDocument(data: data) {
            content = .pdf(pdf)
            preview = Self.firstPage(of: pdf)
        } else if let image = UIImage(data: data) {
            content = .image(image)
            preview = image
        } else if let pdf = PDFDocument(data: data) {
            content = .pdf(pdf)
            preview = Self.firstPage(of: pdf)
        } else {
            throw DocumentLoadError.unreadable
        }
    }

    private static let pdfMagic = Array("%PDF".utf8)

    private static func firstPage(of pdf: PDFDocument) -> UIImage? {
        guard let page = pdf.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        // Cap the long edge: a scanned GST certificate is often A4 at 300dpi,
        // and rasterising that 1:1 to fill a card costs tens of megabytes.
        let scale = min(1600 / max(bounds.width, bounds.height), 3)
        return page.thumbnail(
            of: CGSize(width: bounds.width * scale, height: bounds.height * scale),
            for: .cropBox
        )
    }
}

enum DocumentLoadError: LocalizedError {
    case http(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .http(let code): return "Storage returned \(code)"
        case .unreadable: return "Unsupported file type"
        }
    }
}

// MARK: - Cache

/// Downloads each document once per session and hands the decoded result to
/// every card, thumbnail and full-screen page that asks for it.
///
/// Worth keeping in memory because Supabase serves these `no-cache`, so
/// URLSession's own cache drops them: without this, opening a document
/// full screen re-downloads the same file the card beside it just fetched.
@MainActor
final class DocumentCache {
    static let shared = DocumentCache()

    private var loaded: [URL: LoadedDocument] = [:]
    private var order: [URL] = []
    private var inFlight: [URL: Task<LoadedDocument, Error>] = [:]

    /// A submission has five documents; this leaves room for the one an admin
    /// just came back from without holding every scan they've opened today.
    private let limit = 12

    func cached(for url: URL) -> LoadedDocument? { loaded[url] }

    func document(for url: URL) async throws -> LoadedDocument {
        if let hit = loaded[url] { return hit }
        // Card, thumbnail and full-screen page all ask for the same URL —
        // share the one download between them.
        if let running = inFlight[url] { return try await running.value }

        let task = Task.detached(priority: .userInitiated) { () throws -> LoadedDocument in
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw DocumentLoadError.http(http.statusCode)
            }
            return try LoadedDocument(data: data)
        }
        inFlight[url] = task

        defer { inFlight[url] = nil }
        let document = try await task.value
        store(document, for: url)
        return document
    }

    private func store(_ document: LoadedDocument, for url: URL) {
        if loaded[url] == nil { order.append(url) }
        loaded[url] = document
        while order.count > limit {
            loaded.removeValue(forKey: order.removeFirst())
        }
    }
}

// MARK: - Inline preview

/// Draws a document whole, never cropped — a centre-cropped ID card hides
/// exactly the corners an admin needs to read.
struct DocumentPreview: View {
    let document: ReviewDocument
    /// Set by the caller so a card can show the file type beside the label.
    var onLoad: (LoadedDocument) -> Void = { _ in }

    @State private var loaded: LoadedDocument?
    @State private var failure: String?

    var body: some View {
        ZStack {
            if let image = loaded?.preview {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(document.label)
            } else if let failure {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 18))
                    Text(failure)
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(.gray500)
                .padding(8)
            } else {
                ProgressView()
                    .tint(.gray400)
            }
        }
        .task(id: document.url) { await load() }
    }

    private func load() async {
        guard let url = document.url else { return }
        if let hit = DocumentCache.shared.cached(for: url) {
            loaded = hit
            onLoad(hit)
            return
        }
        loaded = nil
        failure = nil
        do {
            let result = try await DocumentCache.shared.document(for: url)
            loaded = result
            onLoad(result)
        } catch is CancellationError {
            // Scrolled away before it arrived; the next .task reloads it.
        } catch {
            failure = error.localizedDescription
        }
    }
}

// MARK: - Full-screen viewer

/// Drives `fullScreenCover(item:)` — which documents, and which to open on.
struct DocumentViewerRequest: Identifiable {
    let id = UUID()
    let documents: [ReviewDocument]
    let startIndex: Int

    init(documents: [ReviewDocument], startIndex: Int = 0) {
        self.documents = documents
        self.startIndex = startIndex
    }
}

/// A submission's documents, full screen and zoomable, inside the app.
///
/// These used to open with `Link`, which handed the storage URL to Safari and
/// dropped the admin out of a half-finished review. Here an image pinches and
/// double-taps to zoom, swipes sideways to the next document and down to
/// close. A PDF gets PDFKit's own paging view, which brings its own zoom and
/// scrolling — the swipe shortcuts stand aside for it, so its document is
/// changed from the thumbnail strip and closed with the button.
struct DocumentViewer: View {
    let documents: [ReviewDocument]

    @Environment(\.dismiss) private var dismiss

    @State private var selection: Int
    /// True while the page itself is handling drags: a zoomed-in image being
    /// panned, or any PDF. The viewer's own paging/dismiss swipes defer to it.
    @State private var pageOwnsDrag = false
    @State private var dragOffset: CGSize = .zero
    /// Set when a pinch starts, held briefly after it ends. Two moving fingers
    /// also look like a drag, and without this a spread to zoom pages to the
    /// next document instead.
    @State private var didPinch = false

    init(documents: [ReviewDocument], startIndex: Int) {
        let provided = documents.filter(\.isProvided)
        self.documents = provided
        _selection = State(initialValue: provided.indices.contains(startIndex) ? startIndex : 0)
    }

    /// Fades the backdrop as the page is dragged down, so the gesture reads as
    /// putting the document away.
    private var backdropOpacity: Double {
        1 - min(max(dragOffset.height, 0) / 500, 0.6)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backdropOpacity)
                .ignoresSafeArea()

            if documents.isEmpty {
                closeButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
            } else {
                VStack(spacing: 0) {
                    topBar
                    page
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if documents.count > 1 {
                        thumbnailStrip
                    }
                }
            }
        }
        .statusBarHidden()
    }

    // MARK: Chrome

    private var topBar: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(documents[selection].label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                if documents.count > 1 {
                    Text("\(selection + 1) of \(documents.count)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .contentTransition(.opacity)

            HStack {
                closeButton
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(backdropOpacity)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.15), in: Circle())
        }
        .accessibilityLabel("Close document")
    }

    // MARK: Page

    private var page: some View {
        ViewerPage(
            document: documents[selection],
            onPageOwnsDrag: { pageOwnsDrag = $0 },
            onPinchChange: { pinching in
                if pinching {
                    didPinch = true
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragOffset = .zero }
                } else {
                    // Outlive the drag's own onEnded, which fires as the same
                    // fingers lift.
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        didPinch = false
                    }
                }
            }
        )
        .id(documents[selection].id)
        .transition(.opacity)
        .offset(x: dragOffset.width * 0.35, y: max(dragOffset.height, 0))
        .contentShape(Rectangle())
        .simultaneousGesture(viewerDrag, including: pageOwnsDrag ? .subviews : .all)
    }

    private var viewerDrag: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard !didPinch else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height

                guard !didPinch, !pageOwnsDrag else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragOffset = .zero }
                    return
                }

                if dy > 120, abs(dy) > abs(dx) {
                    dismiss()
                    return
                }
                if abs(dx) > 60, abs(dx) > abs(dy) {
                    show(selection + (dx < 0 ? 1 : -1))
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    dragOffset = .zero
                }
            }
    }

    private func show(_ index: Int) {
        guard documents.indices.contains(index), index != selection else { return }
        pageOwnsDrag = false
        withAnimation(.easeInOut(duration: 0.2)) { selection = index }
    }

    // MARK: Thumbnails

    private var thumbnailStrip: some View {
        HStack(spacing: 12) {
            ForEach(Array(documents.enumerated()), id: \.element.id) { index, document in
                Button {
                    show(index)
                } label: {
                    VStack(spacing: 6) {
                        Color.white.opacity(0.08)
                            .frame(width: 60, height: 60)
                            .overlay { DocumentPreview(document: document) }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        index == selection ? Color.white : .white.opacity(0.2),
                                        lineWidth: index == selection ? 2 : 1
                                    )
                            }
                        Text(document.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(index == selection ? .white : .white.opacity(0.6))
                            .lineLimit(1)
                    }
                    // Wide enough for "GST Certificate", the longest label,
                    // which truncated to "GST Certifi…" at 76.
                    .frame(width: 92)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(document.label)
                .accessibilityAddTraits(index == selection ? .isSelected : [])
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
        .opacity(backdropOpacity)
    }
}

// MARK: - One page of the viewer

private struct ViewerPage: View {
    let document: ReviewDocument
    var onPageOwnsDrag: (Bool) -> Void
    var onPinchChange: (Bool) -> Void

    @State private var loaded: LoadedDocument?
    @State private var failure: String?

    var body: some View {
        Group {
            if let loaded {
                switch loaded.content {
                case .image(let image):
                    ZoomableImage(
                        image: image,
                        onZoomChange: onPageOwnsDrag,
                        onPinchChange: onPinchChange
                    )
                case .pdf(let pdf):
                    PDFPageView(document: pdf)
                        // PDFView scrolls and zooms itself; the viewer's swipes
                        // would fight it for the same fingers.
                        .onAppear { onPageOwnsDrag(true) }
                }
            } else if let failure {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                    Text("Couldn't open \(document.label)")
                        .font(.system(size: 15, weight: .medium))
                    Text(failure)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(24)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: document.url) { await load() }
        .onDisappear { onPageOwnsDrag(false) }
    }

    private func load() async {
        guard let url = document.url else { return }
        if let hit = DocumentCache.shared.cached(for: url) {
            loaded = hit
            return
        }
        loaded = nil
        failure = nil
        do {
            loaded = try await DocumentCache.shared.document(for: url)
        } catch is CancellationError {
            // Paged away before it arrived.
        } catch {
            failure = error.localizedDescription
        }
    }
}

// MARK: - Zoom

/// Pinch and double-tap to zoom (up to 6×, enough to read the fine print on an
/// Aadhaar card), pan while zoomed. Panning is clamped so the document can't
/// be dragged off screen.
private struct ZoomableImage: View {
    let image: UIImage
    var onZoomChange: (Bool) -> Void = { _ in }
    var onPinchChange: (Bool) -> Void = { _ in }

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var isPinching = false

    private let maxScale: CGFloat = 6
    private let doubleTapScale: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        if scale > 1 {
                            reset()
                        } else {
                            scale = doubleTapScale
                            baseScale = doubleTapScale
                        }
                    }
                }
                .gesture(magnify(in: geo.size))
                .simultaneousGesture(pan(in: geo.size), including: scale > 1 ? .all : .none)
        }
        .clipped()
        .onChange(of: scale > 1) { _, zoomed in
            onZoomChange(zoomed)
        }
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !isPinching {
                    isPinching = true
                    onPinchChange(true)
                }
                scale = min(max(baseScale * value.magnification, 1), maxScale)
                offset = clamped(offset, in: size)
            }
            .onEnded { _ in
                isPinching = false
                onPinchChange(false)
                if scale <= 1.01 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { reset() }
                } else {
                    baseScale = scale
                    offset = clamped(offset, in: size)
                    baseOffset = offset
                }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clamped(
                    CGSize(
                        width: baseOffset.width + value.translation.width,
                        height: baseOffset.height + value.translation.height
                    ),
                    in: size
                )
            }
            .onEnded { _ in baseOffset = offset }
    }

    private func reset() {
        scale = 1
        baseScale = 1
        offset = .zero
        baseOffset = .zero
    }

    private func clamped(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let maxX = size.width * (scale - 1) / 2
        let maxY = size.height * (scale - 1) / 2
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}

// MARK: - PDF

private struct PDFPageView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .black
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}
