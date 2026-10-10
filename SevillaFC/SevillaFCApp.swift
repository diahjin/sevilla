import SwiftUI
import AVKit
import UniformTypeIdentifiers

@main
struct SevillaFCApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.92, green: 0.08, blue: 0.16))
        }
    }
}

struct StreamItem: Identifiable, Codable, Hashable {
    var id: String { url }
    let name: String
    let url: String
    let group: String
    let logo: String?

    var category: MediaCategory {
        let text = (group + " " + name).lowercased()
        if text.contains("series") || text.contains("serie") || text.contains("season") || text.contains("temporada") { return .series }
        if text.contains("movie") || text.contains("pelicula") || text.contains("película") || text.contains("cinema") || text.contains("vod") { return .movies }
        return .tv
    }
}

enum MediaCategory: String, CaseIterable, Identifiable {
    case tv = "TV", movies = "Películas", series = "Series", favorites = "Favoritos"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .tv: return "tv"; case .movies: return "film"; case .series: return "play.rectangle.on.rectangle"; case .favorites: return "star.fill" }
    }
}

@MainActor final class PlaylistStore: ObservableObject {
    @Published var items: [StreamItem] = []
    @Published var playlistURLs: [String] = []
    @Published var favoriteIDs: Set<String> = []
    @Published var isLoading = false
    @Published var message: String?

    private let urlsKey = "sevilla.playlist.urls"
    private let favoritesKey = "sevilla.favorites"

    init() {
        playlistURLs = UserDefaults.standard.stringArray(forKey: urlsKey) ?? []
        favoriteIDs = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
    }

    func addPlaylist(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            message = "Introduce una URL HTTP o HTTPS válida."; return
        }
        if !playlistURLs.contains(trimmed) { playlistURLs.append(trimmed) }
        UserDefaults.standard.set(playlistURLs, forKey: urlsKey)
        await reloadAll()
    }

    func importPlaylistFile(url: URL) async {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                message = "No se pudo leer el archivo como texto."; return
            }
            let parsed = Self.parseM3U(text)
            guard !parsed.isEmpty else { message = "No se encontraron canales en ese archivo M3U."; return }
            items.append(contentsOf: parsed)
            message = "Importados \(parsed.count) elementos."
        } catch { message = "No se pudo abrir el archivo: \(error.localizedDescription)" }
    }

    func reloadAll() async {
        isLoading = true
        defer { isLoading = false }
        var loaded: [StreamItem] = []
        for raw in playlistURLs {
            guard let url = URL(string: raw) else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 25
                let (data, _) = try await URLSession.shared.data(for: request)
                guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { continue }
                loaded.append(contentsOf: Self.parseM3U(text))
            } catch { message = "No se pudo cargar una lista: \(error.localizedDescription)" }
        }
        // Avoid duplicate streams when the same URL is present in multiple playlists.
        var seen = Set<String>()
        items = loaded.filter { seen.insert($0.url).inserted }
        if items.isEmpty && !playlistURLs.isEmpty && message == nil { message = "La lista no contiene enlaces reconocibles." }
    }

    func toggleFavorite(_ item: StreamItem) {
        if favoriteIDs.contains(item.id) { favoriteIDs.remove(item.id) } else { favoriteIDs.insert(item.id) }
        UserDefaults.standard.set(Array(favoriteIDs), forKey: favoritesKey)
    }

    static func parseM3U(_ text: String) -> [StreamItem] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var result: [StreamItem] = []
        var pendingName = ""
        var pendingGroup = ""
        var pendingLogo: String?
        for line in lines where !line.isEmpty {
            if line.hasPrefix("#EXTINF") {
                let pieces = line.components(separatedBy: ",")
                pendingName = pieces.count > 1 ? pieces.dropFirst().joined(separator: ",").trimmingCharacters(in: .whitespaces) : "Canal sin nombre"
                pendingGroup = attribute("group-title", in: line) ?? "General"
                pendingLogo = attribute("tvg-logo", in: line)
            } else if !line.hasPrefix("#"), let url = URL(string: line), let scheme = url.scheme?.lowercased(), ["http", "https", "rtsp", "rtmp"].contains(scheme) {
                result.append(StreamItem(name: pendingName.isEmpty ? url.host ?? "Canal" : pendingName, url: line, group: pendingGroup, logo: pendingLogo))
                pendingName = ""; pendingGroup = ""; pendingLogo = nil
            }
        }
        return result
    }

    private static func attribute(_ key: String, in line: String) -> String? {
        guard let range = line.range(of: key + "=\"") else { return nil }
        let tail = line[range.upperBound...]
        guard let end = tail.firstIndex(of: "\"") else { return nil }
        return String(tail[..<end])
    }
}

struct MainView: View {
    @StateObject private var store = PlaylistStore()
    @State private var selectedCategory: MediaCategory = .tv
    @State private var searchText = ""
    @State private var playlistText = ""
    @State private var showAddSheet = false
    @State private var showFileImporter = false
    @State private var selectedItem: StreamItem?

    private var visibleItems: [StreamItem] {
        var filtered = store.items
        switch selectedCategory {
        case .tv: filtered = filtered.filter { $0.category == .tv }
        case .movies: filtered = filtered.filter { $0.category == .movies }
        case .series: filtered = filtered.filter { $0.category == .series }
        case .favorites: filtered = filtered.filter { store.favoriteIDs.contains($0.id) }
        }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.group.localizedCaseInsensitiveContains(searchText) }
        }
        return filtered
    }

    var body: some View {
        ZStack {
            Image("SevillaBackground").resizable().scaledToFill().ignoresSafeArea()
                .overlay(LinearGradient(colors: [.black.opacity(0.80), .black.opacity(0.50), .black.opacity(0.96)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            VStack(spacing: 0) {
                header
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(MediaCategory.allCases) { category in
                            Button { selectedCategory = category } label: {
                                Label(category.rawValue, systemImage: category.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(selectedCategory == category ? Color(red: 0.82, green: 0.04, blue: 0.12) : Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal).padding(.vertical, 10)
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.65))
                    TextField("Buscar canales, películas o series", text: $searchText).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(12).background(Color.black.opacity(0.48)).clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal).padding(.bottom, 8)

                if store.isLoading { ProgressView("Cargando lista…").tint(.white).padding() }
                if let message = store.message {
                    Text(message).font(.footnote).foregroundStyle(.white.opacity(0.9)).padding(.horizontal).padding(.vertical, 5)
                }
                if visibleItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "play.rectangle").font(.system(size: 42)).foregroundStyle(.white.opacity(0.75))
                        Text("Todavía no hay contenido").font(.title3.bold())
                        Text("Añade una lista M3U/M3U8 que tengas autorización para utilizar.").font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.75))
                    }.foregroundStyle(.white).padding(.horizontal, 32).padding(.top, 36)
                    Spacer()
                } else {
                    List {
                        ForEach(visibleItems) { item in
                            Button { selectedItem = item } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12)).frame(width: 48, height: 48)
                                        Image(systemName: item.category == .movies ? "film" : item.category == .series ? "play.rectangle" : "tv").font(.title3)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name).font(.headline).lineLimit(2).foregroundStyle(.white)
                                        Text(item.group).font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                                    }
                                    Spacer(minLength: 2)
                                    Button { store.toggleFavorite(item) } label: {
                                        Image(systemName: store.favoriteIDs.contains(item.id) ? "star.fill" : "star")
                                            .foregroundStyle(store.favoriteIDs.contains(item.id) ? .yellow : .white.opacity(0.75)).padding(8)
                                    }.buttonStyle(.plain)
                                }.padding(.vertical, 3)
                            }.listRowBackground(Color.black.opacity(0.48))
                        }
                    }.scrollContentBackground(.hidden).listStyle(.plain)
                }
                bottomActions
            }
        }
        .task { if !store.playlistURLs.isEmpty { await store.reloadAll() } }
        .sheet(isPresented: $showAddSheet) { addPlaylistSheet }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item, .plainText], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await store.importPlaylistFile(url: url) } }
            case .failure(let error): store.message = "Error al importar: \(error.localizedDescription)"
            }
        }
        .fullScreenCover(item: $selectedItem) { item in PlayerScreen(item: item) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("SevillaCrest").resizable().scaledToFit().frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("SEVILLA FC").font(.system(size: 23, weight: .black, design: .rounded)).tracking(1.2)
                Text("TU CONTENIDO, A TU MANERA").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Button { Task { await store.reloadAll() } } label: { Image(systemName: "arrow.clockwise").font(.title3).padding(10).background(.ultraThinMaterial).clipShape(Circle()) }
                .accessibilityLabel("Actualizar listas")
        }.padding(.horizontal).padding(.top, 10).padding(.bottom, 4)
    }

    private var bottomActions: some View {
        HStack(spacing: 10) {
            Button { showAddSheet = true } label: { Label("Añadir URL", systemImage: "link").frame(maxWidth: .infinity).padding(.vertical, 14).background(Color(red: 0.82, green: 0.04, blue: 0.12)).clipShape(RoundedRectangle(cornerRadius: 14)) }
            Button { showFileImporter = true } label: { Label("Importar M3U", systemImage: "doc.badge.plus").frame(maxWidth: .infinity).padding(.vertical, 14).background(Color.white.opacity(0.14)).clipShape(RoundedRectangle(cornerRadius: 14)) }
        }.font(.subheadline.weight(.bold)).padding(.horizontal).padding(.vertical, 10).background(.black.opacity(0.5))
    }

    private var addPlaylistSheet: some View {
        NavigationStack {
            Form {
                Section("Tu lista de reproducción") {
                    TextField("https://servidor/lista.m3u", text: $playlistText).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button { let value = playlistText; Task { await store.addPlaylist(value); if store.message == nil { playlistText = ""; showAddSheet = false } else if store.items.count > 0 { playlistText = ""; showAddSheet = false } } } label: { Label("Guardar y cargar", systemImage: "checkmark.circle.fill") }
                    if !store.playlistURLs.isEmpty {
                        Text("Listas guardadas: \(store.playlistURLs.count)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Importante") { Text("Añade únicamente listas y emisiones para las que tengas permiso. La compatibilidad depende del formato de vídeo y del servidor de origen.") }
            }.navigationTitle("Añadir lista").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { showAddSheet = false } } }
        }
    }
}

struct PlayerScreen: View {
    let item: StreamItem
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { player?.pause(); dismiss() } label: { Label("Volver", systemImage: "chevron.left").font(.headline) }
                    Spacer()
                    Text(item.name).font(.headline).lineLimit(1)
                }.padding()
                if let player {
                    VideoPlayer(player: player).background(.black).onAppear { player.play() }
                } else {
                    ProgressView("Abriendo reproducción…").tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red).padding() }
            }
        }
        .onAppear {
            guard let url = URL(string: item.url) else { errorMessage = "La dirección de vídeo no es válida."; return }
            player = AVPlayer(url: url)
        }
        .onDisappear { player?.pause(); player = nil }
    }
}
