import PaywallSDK
import SwiftUI
import UIKit

private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
}()

/// Placeholder for an empty list (iOS 16 has no `ContentUnavailableView`).
private struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }
}

/// "Akış" tab: one card per SDK call, newest first.
struct FlowView: View {
    @ObservedObject var state: HarnessState
    @ObservedObject var network: NetworkCapture

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(state.logs.isEmpty ? "Her SDK çağrısı burada bir kart olur." : "\(state.logs.count) çağrı · en yeni üstte")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button { UIPasteboard.general.string = state.logsAsJSON() } label: {
                        Label("Akışı kopyala (JSON)", systemImage: "doc.on.doc")
                    }
                    Button { UIPasteboard.general.string = state.currentState.jsonString(pretty: true) } label: {
                        Label("Anlık durumu kopyala", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) { state.clearLogs() } label: { Label("Temizle", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
            }
            .padding(.horizontal, 4)

            if state.logs.isEmpty {
                EmptyState(
                    systemImage: "list.bullet.rectangle",
                    title: "Henüz çağrı yok",
                    message: "Test sekmesinde PaywallSdk.initPaywallSdk ile başla."
                )
            }
            ForEach(Array(state.logs.enumerated().reversed()), id: \.element.id) { index, step in
                FlowCard(number: index + 1, step: step, requests: requests(for: step))
            }
            if !state.logs.isEmpty {
                DetailDisclosure(title: "Anlık durum (current state)") {
                    Mono(text: state.currentState.jsonString(pretty: true))
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func requests(for step: FlowStep) -> [PaywallNetworkEvent] {
        let from = step.startedAt.addingTimeInterval(-0.05)
        let to = step.endedAt.addingTimeInterval(0.05)
        return network.events.filter { $0.startedAt >= from && $0.startedAt <= to }.sorted { $0.startedAt < $1.startedAt }
    }
}

private struct FlowCard: View {
    let number: Int
    let step: FlowStep
    let requests: [PaywallNetworkEvent]

    private var status: (text: String, kind: StatusKind) {
        switch step.normalized?["status"]?.stringValue {
        case "SUCCESS": return ("Başarılı", .success)
        case "ACTION_REQUIRED": return (step.normalized?["actionType"]?.stringValue ?? "Aksiyon", .action)
        case "FAILED": return ("Başarısız", .failed)
        default: return ("Bilgi", .idle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.actionName).font(.subheadline.weight(.semibold))
                    Text("#\(number) · \(timeFormatter.string(from: step.startedAt)) · \(Int(step.endedAt.timeIntervalSince(step.startedAt) * 1000)) ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(text: status.text, kind: status.kind)
            }
            if let guidance = step.guidance {
                GuidanceBox(guidance: guidance)
            } else if let error = step.error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let code = step.code {
                    DetailDisclosure(title: "① Merchant kodu") { Mono(text: code) }
                }
                if let request = step.request {
                    DetailDisclosure(title: "② Parametreler") { Mono(text: request.jsonString(pretty: true)) }
                }
                DetailDisclosure(title: "③ HTTP istekleri (\(requests.count))") {
                    VStack(spacing: 8) {
                        if requests.isEmpty {
                            Hint(text: "İstek yok: SDK cevabı istek göndermeden üretti (ör. parametre kontrolü).")
                        }
                        ForEach(Array(requests.enumerated()), id: \.offset) { _, event in NetworkRow(event: event) }
                    }
                }
                if let response = step.response {
                    DetailDisclosure(title: "④ SdkResponse") { Mono(text: response.jsonString(pretty: true)) }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surfaceContainer))
    }
}

/// "Ağ" tab: HTTP traffic.
struct NetworkView: View {
    @ObservedObject var network: NetworkCapture
    @State private var filter: PaywallNetworkSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker("Filtre", selection: $filter) {
                    Text("Tümü").tag(PaywallNetworkSource?.none)
                    Text("Paywall").tag(Optional(PaywallNetworkSource.paywall))
                    Text("Masterpass").tag(Optional(PaywallNetworkSource.masterpass))
                }
                .pickerStyle(.segmented)
                Menu {
                    Button {
                        UIPasteboard.general.string = visible.map(NetworkCapture.describe)
                            .joined(separator: "\n\n" + String(repeating: "=", count: 40) + "\n\n")
                    } label: { Label("Görünenleri kopyala", systemImage: "doc.on.doc") }
                    Button(role: .destructive) { network.clear() } label: { Label("Temizle", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
            }
            if visible.isEmpty {
                EmptyState(systemImage: "network", title: "Henüz istek yok", message: "Bir SDK fonksiyonu çağırınca istekler burada görünür.")
            } else {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, event in NetworkRow(event: event) }
            }
            Hint(text: "Paywall istekleri eksiksizdir (token ve Authorization maskeli). Masterpass istekleri Masterpass SDK'nın "
                + "içinde yapılır: cevap ve Masterpass'ın kendi log satırları gösterilir; kart verisi Masterpass tarafından şifrelenir.")
                .padding(.horizontal, 4)
        }
    }

    private var visible: [PaywallNetworkEvent] {
        guard let filter else { return network.events }
        return network.events.filter { $0.source == filter }
    }
}

struct NetworkRow: View {
    let event: PaywallNetworkEvent
    @State private var open = false

    private var failed: Bool { event.error != nil || (event.statusCode ?? 0) >= 400 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { open.toggle() } } label: {
                HStack(alignment: .center, spacing: 10) {
                    Text(event.statusCode.map(String.init) ?? "HATA")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(failed ? .red : .green)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(event.method) \(URL(string: event.url)?.path ?? event.url)")
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(event.source == .paywall ? "Paywall" : "Masterpass") · \(event.durationMs) ms · \(timeFormatter.string(from: event.startedAt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Chevron(open: open)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                detail("URL", event.url)
                detail(
                    "Request headers",
                    event.requestHeaders.isEmpty
                        ? "(boş)"
                        : event.requestHeaders.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
                )
                detail("Request", NetworkCapture.prettyJSON(event.requestBody))
                detail("Response", event.error ?? NetworkCapture.prettyJSON(event.responseBody))
                if !event.vendorLogs.isEmpty {
                    detail("Masterpass logları", event.vendorLogs.joined(separator: "\n"))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(failed ? Color.red.opacity(0.08) : Theme.surfaceContainer)
        )
    }

    private func detail(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold))
            Mono(text: text)
        }
    }
}

/// "Rehber" tab.
struct GuideView: View {
    @State private var query = ""

    var body: some View {
        VStack(spacing: 24) {
            FormSection(title: "Test aracı nasıl kullanılır") {
                VStack(alignment: .leading, spacing: 10) {
                    numbered(1, "Bağlantı: ortamı seç, merchant backend'inden alınan token'ı yapıştır, PaywallSdk.initPaywallSdk butonuna bas. Ardından providers.masterpass.initialize otomatik çağrılır.")
                    numbered(2, "Hesap ve kartlar: providers.masterpass.getCardList ile kartları getir. OTP veya linkMerchant gerekirse araç seni yönlendirir.")
                    numbered(3, "Ödeme: kayıtlı kartla ya da yeni kartla öde. OTP penceresi ve 3D sayfası otomatik açılır.")
                    numbered(4, "Her çağrının kodu, isteği ve cevabı Akış sekmesinde; ham HTTP trafiği Ağ sekmesinde.")
                }
                HStack(spacing: 6) {
                    StatusPill(text: "SUCCESS", kind: .success)
                    StatusPill(text: "ACTION", kind: .action)
                    StatusPill(text: "FAILED", kind: .failed)
                }
            }
            FormSection(title: "SDK akışı") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Merchant backend: session + token oluşturur, session bilgilerini token içine ekler.")
                    Text("1. PaywallSdk.initPaywallSdk(environment:token:includeMasterpassSession: true) — SDK session bilgilerini (SessionId, MasterpassToken, UserId, UserPhone) kendisi alır.")
                    Text("2. PaywallSdk.providers.masterpass.initialize() — Masterpass hazırlanır (test aracında otomatik).")
                    Text("3. İşlemler: getCardList (accountAccess), linkMerchant, addCard, deleteCard.")
                    Text("4. Ödeme: payment.initPayment (kayıtlı / manuel kart), payment.registerAndPurchase — sessionId SDK'dan otomatik.")
                    Text("Cevap: 0000 → başarılı · 5001 / 5008 → verifyOtp · 5010 → 3D Secure sayfası · diğer → başarısız.")
                }
                .font(.footnote)
                Link(destination: URL(string: "https://developer.paywall.one/client-side-servisler/2.-yetkilendirme-sdk")!) {
                    Label("Detaylı dokümantasyon", systemImage: "arrow.up.right.square").font(.subheadline)
                }
            }
            FormSection(
                title: "SDK cevabı nasıl işlenir",
                footer: "status'a göre dallan, success'e göre değil: ACTION_REQUIRED'da success da true'dur."
            ) {
                Mono(text: CodeSamples.handling)
                VStack(alignment: .leading, spacing: 6) {
                    Text("• status: SUCCESS / ACTION_REQUIRED / FAILED")
                    Text("• source: SDK (SDK isteği göndermeden durdurdu) · PAYWALL · MASTERPASS")
                    Text("• actionType (yalnızca ACTION_REQUIRED): BANK_OTP, MASTERPASS_OTP, 3D, MERCHANT_LINK_REQUIRED")
                    Text("• errorCode + message (yalnızca FAILED); field: hatalı alan, actionHint: sonraki adım")
                    Text("• data: işleme özel sonuç (kartlar, redirectUrl, paymentId, maskedCard...)")
                    Text("• data.providerMeta: httpStatus, Masterpass responseCode (ör. 0000, 5010) ve raw (ham cevap). data yoksa cevabın kendisinde")
                }
                .font(.footnote)
            }
            FormSection(title: "Hata → ne yapmalı?") {
                ForEach(GuideData.errorActions, id: \.self) { action in
                    Collapsible(title: action.code) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(action.meaning).font(.footnote)
                            ForEach(action.actions, id: \.self) { Text("• \($0)").font(.footnote) }
                            if let flow = action.relatedFlow { Text("İlgili akış: \(flow)").font(.caption) }
                            if let note = action.note { Text("Not: \(note)").font(.caption).foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            FormSection(title: "Masterpass hata kodları") {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Kod veya açıklama ara", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .inputBackground()
                ForEach(GuideData.errorCodeGroups, id: \.title) { group in
                    let codes = filtered(group.codes)
                    if !codes.isEmpty {
                        ErrorCodeGroupView(title: group.title, codes: codes, forceOpen: !query.isBlankText)
                    }
                }
            }
        }
    }

    private func numbered(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.onPrimary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.primary))
            Text(text).font(.footnote).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func filtered(_ codes: [ErrorCodeInfo]) -> [ErrorCodeInfo] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return codes }
        return codes.filter { $0.code.lowercased().contains(text) || $0.description.lowercased().contains(text) }
    }
}

private struct ErrorCodeGroupView: View {
    let title: String
    let codes: [ErrorCodeInfo]
    let forceOpen: Bool
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                HStack {
                    Text(title).foregroundStyle(.primary)
                    Spacer()
                    Text("\(codes.count)").foregroundStyle(.secondary)
                    Chevron(open: open || forceOpen)
                }
                .font(.footnote)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open || forceOpen {
                ForEach(codes, id: \.self) { info in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.code).font(.system(.caption, design: .monospaced).weight(.bold))
                        Text(info.description).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
