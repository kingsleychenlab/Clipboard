import AppKit
import Combine
import SwiftUI

/// Query + filtered results + selection. Kept separate from the view so the
/// keyboard handling (which lives at the AppKit event level) can drive it.
final class OverlayViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: [ClipItem] = []
    @Published var selectedIndex: Int = 0
    /// Drives the scale-in; the window's alpha handles the fade.
    @Published var isPresented: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init(history: ClipboardHistory) {
        Publishers.CombineLatest(history.$items, $query)
            .map { items, query in FuzzyMatch.filter(items, query: query) }
            .sink { [weak self] results in
                self?.results = results
                // Any change to the result set invalidates the old position.
                self?.selectedIndex = 0
            }
            .store(in: &cancellables)
    }

    var selectedItem: ClipItem? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    /// Moves selection, clamped — no wraparound, which makes holding an arrow
    /// key at the end of the list feel stable rather than jumping to the far end.
    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), results.count - 1)
    }

    func reset() {
        query = ""
        selectedIndex = 0
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayViewModel
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            queryField
            Divider().opacity(0.5)
            resultList
        }
        .background(
            // Vibrancy behind the content, so the overlay reads as a system
            // surface rather than a flat rectangle.
            VisualEffectBackground()
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        // Scales up from just-under full size. Subtle on purpose: the overlay
        // should read as already-there, not as an animation you wait through.
        .scaleEffect(model.isPresented ? 1 : 0.96)
        .animation(.spring(response: 0.22, dampingFraction: 0.9), value: model.isPresented)
    }

    private var queryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13, weight: .medium))

            TextField("Search clipboard…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($queryFocused)
                .onAppear { queryFocused = true }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                        ClipRow(item: item, isSelected: index == model.selectedIndex)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture { model.selectedIndex = index }
                    }
                }
                .padding(6)
            }
            .onChange(of: model.selectedIndex) { _ in
                guard let item = model.selectedItem else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(item.id, anchor: .bottom)
                }
            }
            .overlay {
                if model.results.isEmpty {
                    Text(model.query.isEmpty ? "No clips yet" : "No matches")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 13))
                }
            }
        }
    }
}

struct ClipRow: View {
    let item: ClipItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon
            Text(item.preview)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .text:
            Image(systemName: "text.alignleft")
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                .frame(width: 16)
        case .image:
            if let data = item.imageData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                    .frame(width: 16)
            }
        }
    }
}

/// NSVisualEffectView bridge — SwiftUI's `.ultraThinMaterial` doesn't blur the
/// desktop behind a borderless panel the way the AppKit view does.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
