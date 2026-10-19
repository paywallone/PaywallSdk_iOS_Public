import PaywallSDK
import SwiftUI
import UIKit

/// "Test" tab: progress, 1) connection, 2) account / cards, 3) payment, OTP result.
struct HarnessView: View {
    @ObservedObject var state: HarnessState

    var body: some View {
        VStack(spacing: 24) {
            ProgressHeader(
                state: state,
                sdkInit: state.sdkInit,
                providerInit: state.providerInit,
                cardList: state.cardList,
                registered: state.registeredPayment,
                manual: state.manualPayment
            )
            ConnectionSection(state: state, sdkInit: state.sdkInit, providerInit: state.providerInit)
            AccountSection(state: state, cardList: state.cardList, cardDelete: state.cardDelete)
            PaymentSection(state: state, cardNumber: state.cardNumber, cvv: state.cvv, terms: state.terms)
            OtpSection(action: state.otpVerify)
        }
    }
}

// MARK: - Progress

private struct ProgressHeader: View {
    @ObservedObject var state: HarnessState
    @ObservedObject var sdkInit: ActionState
    @ObservedObject var providerInit: ActionState
    @ObservedObject var cardList: ActionState
    @ObservedObject var registered: ActionState
    @ObservedObject var manual: ActionState

    private var paymentKind: StatusKind {
        if registered.success || manual.success { return .success }
        if registered.actionRequired || manual.actionRequired || state.threeD != nil { return .action }
        if registered.error != nil || manual.error != nil { return .failed }
        return .idle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Step(number: 1, title: "SDK", kind: sdkInit.kind, loading: sdkInit.loading)
            Connector()
            Step(number: 2, title: "Masterpass", kind: providerInit.kind, loading: providerInit.loading)
            Connector()
            Step(
                number: 3,
                title: state.cards.isEmpty ? "Kartlar" : "Kartlar (\(state.cards.count))",
                kind: cardList.kind,
                loading: cardList.loading
            )
            Connector()
            Step(number: 4, title: "Ödeme", kind: paymentKind, loading: registered.loading || manual.loading)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private struct Step: View {
        let number: Int
        let title: String
        let kind: StatusKind
        let loading: Bool

        var body: some View {
            VStack(spacing: 6) {
                ZStack {
                    if loading {
                        ProgressView()
                    } else if kind == .idle {
                        Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
                        Text("\(number)").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: kind.icon).font(.title2).foregroundStyle(kind.color)
                    }
                }
                .frame(width: 28, height: 28)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(kind == .idle ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private struct Connector: View {
        var body: some View {
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 14, height: 1.5).padding(.top, 14)
        }
    }
}

// MARK: - 1) Connection

private struct ConnectionSection: View {
    @ObservedObject var state: HarnessState
    @ObservedObject var sdkInit: ActionState
    @ObservedObject var providerInit: ActionState

    private var locked: Bool { sdkInit.success }

    var body: some View {
        FormSection(
            title: "1 · Bağlantı",
            footer: "Token'ı merchant backend'i üretir. initPaywallSdk başarılı olunca providers.masterpass.initialize() otomatik çağrılır."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Ortam", selection: $state.environment) {
                    ForEach(PaywallEnvironment.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Access token").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if !locked {
                            Button {
                                if let text = UIPasteboard.general.string { state.accessToken = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                            } label: {
                                Label("Yapıştır", systemImage: "doc.on.clipboard").font(.caption)
                            }
                        }
                    }
                    TextField("Token'ı buraya yapıştır", text: $state.accessToken, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.system(.footnote, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.vertical, 10)
                        .inputBackground()
                }
                Toggle(isOn: $state.includeMasterpassSession) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Masterpass session'ı dahil et").font(.subheadline)
                        Hint(text: "Telefon ve userId token'dan otomatik dolar.")
                    }
                }
            }
            .disabled(locked)

            ActionRow(
                function: "PaywallSdk.initPaywallSdk(...)",
                label: locked ? "SDK başlatıldı" : "Token'ı doğrular, session'ı başlatır",
                action: sdkInit,
                enabled: !state.accessToken.isBlankText && !locked
            ) { state.initPaywallSdk() }

            if state.sessionId != nil && (providerInit.hasResult || providerInit.loading) && !providerInit.success {
                ActionRow(
                    function: "providers.masterpass.initialize()",
                    label: "Masterpass'ı tekrar başlat",
                    action: providerInit,
                    prominent: false
                ) { state.initMasterpassProvider() }
            } else if providerInit.success {
                Label("providers.masterpass.initialize() başarılı", systemImage: StatusKind.success.icon)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - 2) Account / cards

private struct AccountSection: View {
    @ObservedObject var state: HarnessState
    @ObservedObject var cardList: ActionState
    @ObservedObject var cardDelete: ActionState

    var body: some View {
        FormSection(
            title: "2 · Hesap ve kartlar",
            footer: state.isProviderAndSessionReady ? nil : "Önce 1. adımda initPaywallSdk(...) çağır."
        ) {
            HStack(spacing: 10) {
                Field(label: "Telefon (accountKey)", text: $state.userPhone, keyboard: .phonePad)
                Field(label: "User ID", text: $state.userId)
            }

            ActionRow(
                function: "providers.masterpass.getCardList(...)",
                label: "Kayıtlı kartları getirir (Account Access)",
                action: cardList,
                enabled: state.isProviderAndSessionReady
            ) { state.accountAccess() }

            if !state.cards.isEmpty {
                VStack(spacing: 0) {
                    ForEach(state.cards) { card in
                        CardListRow(card: card, deleting: cardDelete.loading) { state.cardToDelete = card }
                        if card != state.cards.last { Divider().padding(.leading, 44) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill)))
            }

            ResultView(action: cardDelete)

            Collapsible(title: "Merchant link", summary: "linkMerchant", systemImage: "link") {
                Hint(text: "Kart listesi \"hesap bu merchant'a bağlı değil\" derse kullanılır; OTP isteyebilir.")
                ActionRow(
                    function: "providers.masterpass.linkMerchant(...)",
                    label: "Hesabı bu merchant'a bağlar",
                    action: state.merchantLink,
                    enabled: state.isProviderAndSessionReady,
                    prominent: false
                ) { state.merchantLinkAction() }
            }
        }
    }
}

private struct CardListRow: View {
    let card: CardRow
    let deleting: Bool
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "creditcard.fill").foregroundStyle(.tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(card.alias).font(.subheadline.weight(.semibold))
                    if card.isDefault {
                        Text("Varsayılan")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                }
                Text(card.masked).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(deleting)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - 3) Payment

private enum PayMode: Hashable { case registered, newCard }

private struct PaymentSection: View {
    @ObservedObject var state: HarnessState
    @ObservedObject var cardNumber: PaywallCardNumberState
    @ObservedObject var cvv: PaywallSecureTextState
    @ObservedObject var terms: PaywallTermsState
    @State private var mode: PayMode = .registered

    var body: some View {
        FormSection(
            title: "3 · Ödeme",
            footer: state.isProviderAndSessionReady ? nil : "Ödeme için önce initPaywallSdk(...) çağır."
        ) {
            amountRow
            Divider()
            OrderDetails(state: state)
            Divider()
            Picker("Ödeme yöntemi", selection: $mode) {
                Text("Kayıtlı kart").tag(PayMode.registered)
                Text("Yeni kart").tag(PayMode.newCard)
            }
            .pickerStyle(.segmented)

            switch mode {
            case .registered: registeredCard
            case .newCard: newCard
            }

            if let threeD = state.threeD {
                VStack(alignment: .leading, spacing: 8) {
                    Label("3D Secure bekleniyor", systemImage: "lock.shield").font(.subheadline.weight(.semibold))
                    Text(threeD.url.absoluteString)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Button("3D sayfasını aç") { state.threeDOpen = threeD }.buttonStyle(.borderedProminent)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.1)))
            }
        }
    }

    private var amountRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tutar").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                TextField("0.00", text: $state.paymentAmount)
                    .keyboardType(.decimalPad)
                    .font(.title3.weight(.semibold))
                    .inputBackground()
                if state.paymentAmount != formatted(state.productTotal) {
                    Button { state.updatePaymentAmountFromProducts() } label: {
                        Label("Ürün toplamı: \(formatted(state.productTotal))", systemImage: "arrow.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder private var registeredCard: some View {
        if state.cards.isEmpty {
            Hint(text: "Kayıtlı kart yok. 2. adımda getCardList ile listeyi al ya da \"Yeni kart\" ile öde.")
        } else {
            HStack {
                Text("Kart").font(.subheadline)
                Spacer()
                Picker("Kart", selection: $state.selectedCardAlias) {
                    Text("Kart seç").tag(String?.none)
                    ForEach(state.cards) { card in Text("\(card.alias) · \(card.masked)").tag(Optional(card.alias)) }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill)))
        }
        ActionRow(
            function: "payment.initPayment(.registeredCard)",
            label: "Seçili kayıtlı kartla öder",
            action: state.registeredPayment,
            enabled: state.isProviderAndSessionReady && state.selectedCard != nil
        ) { state.payWithRegisteredCard() }
    }

    @ViewBuilder private var newCard: some View {
        SecureFieldFrame(
            label: "Kart numarası",
            info: cardNumber.digitCount == 0
                ? nil
                : "\(cardNumber.digitCount) hane · BIN \(cardNumber.bin ?? "-") · \(cardNumber.isValid ? "geçerli ✓" : "geçersiz")"
        ) {
            PaywallCardNumberFieldView(state: cardNumber, placeholder: "0000 0000 0000 0000", configure: plainSecureField)
        }
        Field(label: "Kart sahibi", text: $state.cardHolderName)
        HStack(alignment: .top, spacing: 10) {
            Field(label: "Ay", text: twoDigits($state.expiryMonth), placeholder: "AA", keyboard: .numberPad)
            Field(label: "Yıl", text: twoDigits($state.expiryYear), placeholder: "YY", keyboard: .numberPad)
            SecureFieldFrame(label: "CVV") {
                PaywallSecureTextFieldView(state: cvv, placeholder: "•••", configure: plainSecureField)
            }
        }
        Field(label: "Kart adı (alias)", text: $state.cardAlias)
        PaywallTermsCheckBoxView(state: terms).frame(minHeight: 32)
        Toggle(isOn: $state.saveCardOnPayment) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Kartı kaydet ve öde").font(.subheadline)
                Hint(text: "Kart kaydı ve ödeme tek seferde yapılır.")
            }
        }
        ActionRow(
            function: state.saveCardOnPayment ? "payment.registerAndPurchase(...)" : "payment.initPayment(.manualCard)",
            label: state.saveCardOnPayment ? "Kartı kaydeder ve öder" : "Yeni kartla öder (kaydetmeden)",
            action: state.manualPayment,
            enabled: state.isProviderAndSessionReady
        ) { state.payWithManualCard() }
        ActionRow(
            function: "providers.masterpass.addCard(...)",
            label: "Sadece kartı kaydeder",
            action: state.addCard,
            enabled: state.isProviderAndSessionReady,
            prominent: false
        ) { state.addCardToMasterpass() }
    }

    private func twoDigits(_ binding: Binding<String>) -> Binding<String> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = String($0.prefix(2)) })
    }
}

/// Customer, products and redirect URLs: prefilled, so collapsed by default.
private struct OrderDetails: View {
    @ObservedObject var state: HarnessState

    private var customerMissing: Bool {
        state.customerFullName.isBlankText || state.customerEmail.isBlankText || state.customerIdentityNumber.isBlankText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Collapsible(
                title: "Müşteri",
                summary: customerMissing ? "Eksik bilgi" : state.customerFullName,
                systemImage: "person"
            ) {
                Field(label: "Ad soyad *", text: $state.customerFullName)
                Field(label: "E-posta *", text: $state.customerEmail, keyboard: .emailAddress)
                HStack(alignment: .top, spacing: 10) {
                    Field(label: "TC kimlik no *", text: $state.customerIdentityNumber, keyboard: .numberPad)
                    Field(label: "Telefon", text: $state.customerPhone, keyboard: .phonePad)
                }
                Hint(text: "* Her ödeme isteğinde gönderilir; telefon isteğe bağlı.")
            }
            Collapsible(
                title: "Ürünler",
                summary: "\(state.products.count) ürün · \(formatted(state.productTotal))",
                systemImage: "cart"
            ) {
                ForEach(state.products) { product in
                    ProductRowView(product: product, canRemove: state.products.count > 1) { state.removeProduct(product) }
                }
                Button { state.addProduct() } label: { Label("Ürün ekle", systemImage: "plus") }
                    .font(.subheadline)
            }
            Collapsible(title: "Yönlendirme adresleri", summary: "3D dönüşü", systemImage: "arrow.uturn.backward") {
                Field(label: "Success URL", text: $state.successUrl, keyboard: .URL)
                Field(label: "Fail URL", text: $state.failUrl, keyboard: .URL)
            }
        }
    }
}

private struct ProductRowView: View {
    @ObservedObject var product: ProductRow
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Field(label: "Kod", text: $product.code)
                Field(label: "Ad", text: $product.name)
            }
            HStack(alignment: .top, spacing: 10) {
                Field(label: "Adet", text: $product.quantity, keyboard: .numberPad)
                Field(label: "Fiyat", text: $product.price, keyboard: .decimalPad)
                Field(label: "KDV %", text: $product.vatRate, keyboard: .numberPad)
            }
            HStack {
                Text("Satır toplamı: \(formatted(product.total))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if canRemove {
                    Button("Kaldır", role: .destructive, action: remove).font(.caption)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.secondary.opacity(0.2)))
    }
}

// MARK: - OTP

private struct OtpSection: View {
    @ObservedObject var action: ActionState

    var body: some View {
        if action.hasResult || action.loading {
            FormSection(title: "Son OTP doğrulaması") {
                if action.loading {
                    HStack(spacing: 8) { ProgressView(); Text("Doğrulanıyor…").font(.footnote) }
                }
                ResultView(action: action)
            }
        }
    }
}

private func formatted(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
