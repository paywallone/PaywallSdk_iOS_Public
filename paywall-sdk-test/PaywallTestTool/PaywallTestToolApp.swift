import PaywallSDK
import SwiftUI

@main
struct PaywallTestToolApp: App {
    @StateObject private var state = HarnessState()
    @StateObject private var network = NetworkCapture()

    var body: some Scene {
        WindowGroup {
            ContentView(state: state, network: network)
                .tint(Theme.primary)
                .onAppear { PaywallSdk.setNetworkListener(network) }
        }
    }
}

/// Top bar, 4 tabs (Test / Akış / Ağ / Rehber) and the sheets.
struct ContentView: View {
    @ObservedObject var state: HarnessState
    @ObservedObject var network: NetworkCapture
    @State private var tab = 0
    @State private var showRefresh = false

    var body: some View {
        TabView(selection: $tab) {
            page { HarnessView(state: state) }
                .tabItem { Label("Test", systemImage: "creditcard") }
                .tag(0)
            page { FlowView(state: state, network: network) }
                .tabItem { Label("Akış", systemImage: "list.bullet.rectangle") }
                .badge(state.logs.count)
                .tag(1)
            page { NetworkView(network: network) }
                .tabItem { Label("Ağ", systemImage: "network") }
                .badge(network.events.count)
                .tag(2)
            page { GuideView() }
                .tabItem { Label("Rehber", systemImage: "book") }
                .tag(3)
        }
        .confirmationDialog("Test aracını sıfırla", isPresented: $showRefresh, titleVisibility: .visible) {
            Button("Sıfırla") { refresh(clearSavedFields: false) }
            Button("Sıfırla ve alanları sil", role: .destructive) { refresh(clearSavedFields: true) }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Session, kartlar, OTP/3D adımları ve loglar sıfırlanır; form alanları korunur. "
                + "Kart numarası ve CVV hiç kaydedilmez. Koşul onay kutusu programatik olarak temizlenemez.")
        }
        .sheet(item: $state.otpRequest, onDismiss: {
            if state.otpRequest == nil && state.otpVerify.loading == false { state.cancelOtp() }
        }) { request in
            OtpSheet(state: state, request: request)
        }
        .alert(
            "Kart silinsin mi?",
            isPresented: Binding(get: { state.cardToDelete != nil }, set: { if !$0 { state.cardToDelete = nil } }),
            presenting: state.cardToDelete
        ) { _ in
            Button("PaywallSdk.providers.masterpass.deleteCard", role: .destructive) { state.deleteCard() }
            Button("Vazgeç", role: .cancel) { state.cardToDelete = nil }
        } message: { card in
            Text("\"\(card.alias)\" kartı Masterpass hesabından kaldırılacak.")
        }
        .fullScreenCover(item: $state.threeDOpen) { request in
            ThreeDSheet(request: request) { result, lastUrl in state.onThreeDFinished(result, lastUrl: lastUrl) }
        }
    }

    /// One tab: grouped background, scrollable content, shared toolbar.
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack {
            ScrollView {
                content().padding(.horizontal, 16).padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Paywall Test").font(.headline)
                        HStack(spacing: 4) {
                            Text(state.environment.rawValue.uppercased()).bold().foregroundStyle(environmentColor)
                            Text("· SDK \(PaywallSdk.version) · Masterpass \(PaywallSdk.masterpassVersion)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption2)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showRefresh = true } label: { Image(systemName: "arrow.counterclockwise") }
                        .accessibilityLabel("Sıfırla")
                }
            }
        }
    }

    private var environmentColor: Color {
        switch state.environment {
        case .prod: return .red
        case .test: return .orange
        case .dev: return .blue
        }
    }

    private func refresh(clearSavedFields: Bool) {
        state.refresh(clearSavedFields: clearSavedFields)
        network.clear()
        tab = 0
    }
}
