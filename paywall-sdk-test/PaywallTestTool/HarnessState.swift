import Foundation
import PaywallSDK
import SwiftUI

/// One button's state.
final class ActionState: ObservableObject {
    @Published var loading = false
    @Published var success = false
    @Published var error: String?
    @Published var response: PaywallJSON?
    @Published var status: SdkStatus?
    @Published var guidance: Guidance?
    @Published var code: String?

    var actionRequired: Bool { status == .actionRequired }

    func start() {
        loading = true
        success = false
        error = nil
        response = nil
        status = nil
        guidance = nil
    }

    func reset() {
        start()
        loading = false
        code = nil
    }
}

struct CardRow: Identifiable, Hashable {
    let alias: String
    let masked: String
    let bin: String
    let isDefault: Bool
    let uniqueCardNumber: String?

    var id: String { alias }
}

final class ProductRow: ObservableObject, Identifiable {
    let id = UUID()
    @Published var code: String
    @Published var name: String
    @Published var quantity: String
    @Published var price: String
    @Published var vatRate: String

    init(_ code: String, _ name: String, _ quantity: String, _ price: String, _ vatRate: String) {
        self.code = code
        self.name = name
        self.quantity = quantity
        self.price = price
        self.vatRate = vatRate
    }

    /// Price × quantity; VAT is shown but not added.
    var total: Decimal {
        let price = Decimal(string: price.replacingOccurrences(of: ",", with: ".")) ?? 0
        let quantity = Decimal(string: quantity) ?? 0
        return price * quantity
    }
}

/// One SDK call in the "Akış" tab.
struct FlowStep: Identifiable {
    let id = UUID()
    let startedAt: Date
    let endedAt: Date
    let actionName: String
    var code: String?
    var request: PaywallJSON?
    var response: PaywallJSON?
    var normalized: PaywallJSON?
    var guidance: Guidance?
    var error: String?
}

struct OtpRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let pendingAction: String
}

struct ThreeDRequest: Identifiable {
    let id = UUID()
    let url: URL
    let successUrl: String?
    let failUrl: String?
}

/// Form fields kept between launches (UserDefaults).
/// Card number, CVV and OTP are never saved: they live only in the SDK secure fields.
enum SavedField: String, CaseIterable {
    case accessToken, includeMasterpassSession, userPhone, userId, paymentAmount, successUrl, failUrl
    case customerFullName, customerPhone, customerEmail, customerIdentityNumber
    case cardHolderName, expiryMonth, expiryYear, cardAlias, saveCardOnPayment

    static let suiteName = "test-tool-fields"
}

/// All state and actions of the sample app.
@MainActor
final class HarnessState: ObservableObject {
    private let defaults = UserDefaults(suiteName: SavedField.suiteName) ?? .standard

    // Secure inputs (SDK components). Created once so values survive tab switches.
    let cardNumber = PaywallCardNumberState()
    let cvv = PaywallSecureTextState(kind: .cvv)
    let otp = PaywallSecureTextState(kind: .otp)
    let terms = PaywallTermsState(titleText: "Masterpass kullanım koşullarını kabul ediyorum (kart kaydı için zorunlu)")

    // ========== CONFIGURATION ==========
    @Published var environment: PaywallEnvironment = .dev
    @Published var accessToken: String { didSet { save(.accessToken, accessToken) } }
    @Published var includeMasterpassSession: Bool { didSet { save(.includeMasterpassSession, includeMasterpassSession) } }

    // ========== ACCOUNT ==========
    @Published var userPhone: String { didSet { save(.userPhone, userPhone) } }
    @Published var userId: String { didSet { save(.userId, userId) } }

    // ========== PAYMENT ==========
    @Published var paymentAmount: String { didSet { save(.paymentAmount, paymentAmount) } }
    @Published var successUrl: String { didSet { save(.successUrl, successUrl) } }
    @Published var failUrl: String { didSet { save(.failUrl, failUrl) } }
    @Published var customerFullName: String { didSet { save(.customerFullName, customerFullName) } }
    @Published var customerPhone: String { didSet { save(.customerPhone, customerPhone) } }
    @Published var customerEmail: String { didSet { save(.customerEmail, customerEmail) } }
    @Published var customerIdentityNumber: String { didSet { save(.customerIdentityNumber, customerIdentityNumber) } }
    @Published var cardHolderName: String { didSet { save(.cardHolderName, cardHolderName) } }
    @Published var expiryMonth: String { didSet { save(.expiryMonth, expiryMonth) } }
    @Published var expiryYear: String { didSet { save(.expiryYear, expiryYear) } }
    @Published var cardAlias: String { didSet { save(.cardAlias, cardAlias) } }
    @Published var saveCardOnPayment: Bool { didSet { save(.saveCardOnPayment, saveCardOnPayment) } }
    @Published var products: [ProductRow] = [ProductRow("TEST-PRODUCT-001", "Test Product", "1", "100", "0")]
    let trackingCode = "TRACK-\(Int(Date().timeIntervalSince1970 * 1000))"

    // ========== ACTION STATES ==========
    let sdkInit = ActionState()
    let providerInit = ActionState()
    let cardList = ActionState()
    let merchantLink = ActionState()
    let cardDelete = ActionState()
    let addCard = ActionState()
    let registeredPayment = ActionState()
    let manualPayment = ActionState()
    let otpVerify = ActionState()

    @Published var sessionId: String?
    @Published var cards: [CardRow] = []
    @Published var cardToDelete: CardRow?
    @Published var linkedState = false
    @Published var selectedCardAlias: String?

    // ========== OTP ==========
    @Published var otpRequest: OtpRequest?
    @Published var otpResendMessage: String?
    @Published var otpResendLoading = false
    private var awaitingOtp = false
    private var pendingAction: String?

    // ========== 3D ==========
    @Published var threeD: ThreeDRequest?
    @Published var threeDOpen: ThreeDRequest?

    // ========== DEBUG ==========
    @Published var logs: [FlowStep] = []

    private var tasks: [Task<Void, Never>] = []

    init() {
        let defaults = self.defaults
        func text(_ field: SavedField, _ fallback: String) -> String { defaults.string(forKey: field.rawValue) ?? fallback }
        func flag(_ field: SavedField, _ fallback: Bool) -> Bool {
            defaults.object(forKey: field.rawValue) == nil ? fallback : defaults.bool(forKey: field.rawValue)
        }
        accessToken = text(.accessToken, "")
        includeMasterpassSession = flag(.includeMasterpassSession, true)
        userPhone = text(.userPhone, "")
        userId = text(.userId, "")
        paymentAmount = text(.paymentAmount, "100")
        successUrl = text(.successUrl, "https://merchant.com/success")
        failUrl = text(.failUrl, "https://merchant.com/fail")
        customerFullName = text(.customerFullName, "Test User")
        customerPhone = text(.customerPhone, "")
        customerEmail = text(.customerEmail, "test@example.com")
        customerIdentityNumber = text(.customerIdentityNumber, "12345678901")
        cardHolderName = text(.cardHolderName, "")
        expiryMonth = text(.expiryMonth, "12")
        expiryYear = text(.expiryYear, "26")
        cardAlias = text(.cardAlias, "")
        saveCardOnPayment = flag(.saveCardOnPayment, false)
    }

    private func save(_ field: SavedField, _ value: Any) { defaults.set(value, forKey: field.rawValue) }

    var allActions: [ActionState] {
        [sdkInit, providerInit, cardList, merchantLink, cardDelete, addCard, registeredPayment, manualPayment, otpVerify]
    }

    var selectedCard: CardRow? { cards.first { $0.alias == selectedCardAlias } }

    /// True when the Masterpass provider is initialized and a session exists.
    var isProviderAndSessionReady: Bool { providerInit.success && sessionId != nil }

    var productTotal: Decimal { products.reduce(0) { $0 + $1.total } }

    var currentState: PaywallJSON {
        .object([
            "currentToken": SdkJSON.maskToken(accessToken.isEmpty ? nil : accessToken),
            "sessionId": sessionId.map(PaywallJSON.string) ?? .null,
            "providerInitialized": .bool(providerInit.success),
            "linkedState": .bool(linkedState),
            "cardCount": .number(String(cards.count)),
            "environment": .string(environment.wireValue),
            "userId": userId.isEmpty ? .null : .string(userId),
            "userPhone": userPhone.isEmpty ? .null : .string(userPhone),
            "awaitingOtp": .bool(awaitingOtp),
            "pendingAction": pendingAction.map(PaywallJSON.string) ?? .null,
        ])
    }

    /// "Yenile": starts the flow over. Running calls are stopped; statuses, session, cards,
    /// OTP / 3D steps, logs and the secure fields are cleared. Saved form fields stay unless `clearSavedFields` is set.
    /// The SDK state is replaced on the next "Init Paywall SDK".
    func refresh(clearSavedFields: Bool) {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        allActions.forEach { $0.reset() }
        sessionId = nil
        cards = []
        cardToDelete = nil
        linkedState = false
        selectedCardAlias = nil
        otpRequest = nil
        otpResendMessage = nil
        otpResendLoading = false
        awaitingOtp = false
        pendingAction = nil
        threeD = nil
        threeDOpen = nil
        logs = []
        cardNumber.clear()
        cvv.clear()
        otp.clear()
        if clearSavedFields {
            SavedField.allCases.forEach { defaults.removeObject(forKey: $0.rawValue) }
            environment = .dev
            accessToken = ""
            includeMasterpassSession = true
            userPhone = ""
            userId = ""
            paymentAmount = "100"
            successUrl = "https://merchant.com/success"
            failUrl = "https://merchant.com/fail"
            customerFullName = "Test User"
            customerPhone = ""
            customerEmail = "test@example.com"
            customerIdentityNumber = "12345678901"
            cardHolderName = ""
            expiryMonth = "12"
            expiryYear = "26"
            cardAlias = ""
            saveCardOnPayment = false
            products = [ProductRow("TEST-PRODUCT-001", "Test Product", "1", "100", "0")]
        }
    }

    // ========== A) SDK / SESSION CONTROL PANEL ==========

    func initPaywallSdk() {
        if accessToken.trimmingCharacters(in: .whitespaces).isEmpty {
            sdkInit.error = "Token is required"
            return
        }
        launch(sdkInit) { [self] in
            let environment = self.environment
            let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let includeSession = includeMasterpassSession
            let response = await record(
                sdkInit,
                "PaywallSdk.initPaywallSdk",
                CodeSamples.initPaywallSdk(environment, includeSession),
                .object([
                    "environment": .string(environment.wireValue),
                    "includeMasterpassSession": .bool(includeSession),
                    "token": SdkJSON.maskToken(token),
                ])
            ) { await PaywallSdk.initPaywallSdk(environment: environment, token: token, includeMasterpassSession: includeSession) }

            if response.success, let data = response.data, data.sdkInitialized {
                sdkInit.success = true
                if data.hasMasterpassSession, let masterpass = data.body?.masterpass {
                    // Session info comes from the token; fill the form.
                    sessionId = masterpass.sessionId
                    if let value = masterpass.userId { userId = value }
                    if let value = masterpass.userPhone { userPhone = value }
                    // The provider is initialized automatically right after InitPaywallSdk.
                    await runProviderInit(auto: true)
                }
            } else {
                sdkInit.error = response.message ?? "SDK initialization failed"
            }
        }
    }

    func initMasterpassProvider() {
        if !sdkInit.success || sessionId == nil {
            providerInit.error = "SDK and Session must be initialized first (use InitPaywallSdk)"
            return
        }
        launch(providerInit) { [self] in await runProviderInit(auto: false) }
    }

    private func runProviderInit(auto: Bool) async {
        providerInit.start()
        defer { providerInit.loading = false }
        let response = await record(
            providerInit,
            "providers.masterpass.initialize",
            CodeSamples.providerInit(),
            .object(["auto": .bool(auto)])
        ) { await PaywallSdk.providers.masterpass.initialize() }
        if response.success, response.data?.masterpassSdkInitialized == true {
            providerInit.success = true
        } else {
            providerInit.error = response.message ?? "Provider initialization failed"
        }
    }

    // ========== B) ACCOUNT / CARD OPERATIONS ==========

    func accountAccess() {
        guard accountGuards(cardList) else { return }
        launch(cardList) { [self] in await runAccountAccess() }
    }

    private func runAccountAccess() async {
        cardList.start()
        defer { cardList.loading = false }
        let accountKey = userPhone
        let user = userId.trimmingCharacters(in: .whitespaces)
        let response = await record(
            cardList,
            "providers.masterpass.getCardList",
            CodeSamples.getCardList(accountKey, user),
            .object(["accountKey": .string(accountKey), "accountKeyType": .string("Msisdn"), "userId": .string(user)])
        ) {
            await PaywallSdk.providers.masterpass.getCardList(GetCardListParams(accountKey: accountKey, userId: user, accountKeyType: .msisdn))
        }

        if openOtpIfRequired(response, "accountAccess") { return }
        if response.status == .success {
            cards = (response.data?.cards ?? []).map { card in
                CardRow(
                    alias: card.cardAlias ?? "",
                    masked: card.maskedCardNumber ?? "****",
                    bin: card.cardBin ?? "",
                    isDefault: card.isDefaultCard == true,
                    uniqueCardNumber: card.uniqueCardNumber
                )
            }
            cardList.success = true
            linkedState = !cards.isEmpty
            if selectedCard == nil { selectedCardAlias = nil }
        } else {
            cardList.error = response.message ?? "Get card list failed"
        }
    }

    func merchantLinkAction() {
        guard accountGuards(merchantLink) else { return }
        launch(merchantLink) { [self] in
            let accountKey = userPhone
            let response = await record(
                merchantLink,
                "providers.masterpass.linkMerchant",
                CodeSamples.linkMerchant(accountKey),
                .object(["accountKey": .string(accountKey)])
            ) { await PaywallSdk.providers.masterpass.linkMerchant(LinkMerchantParams(accountKey: accountKey)) }

            if openOtpIfRequired(response, "merchantLink") { return }
            if response.status == .success {
                merchantLink.success = true
                linkedState = true
            } else {
                let message = response.message ?? "Merchant link failed"
                merchantLink.error = response.errorCode == "ACCOUNT_NOT_FOUND" || response.providerMeta?.httpStatus == 404
                    ? "Account not found (404). This may happen after deleting all cards. Error: \(message)"
                    : message
            }
        }
    }

    func deleteCard() {
        guard let card = cardToDelete else { return }
        cardToDelete = nil
        if userPhone.trimmingCharacters(in: .whitespaces).isEmpty {
            cardList.error = "UserPhone (accountKey) is required"
            return
        }
        if userId.trimmingCharacters(in: .whitespaces).isEmpty {
            cardDelete.error = "userId is required"
            return
        }
        launch(cardDelete) { [self] in
            let accountKey = userPhone
            let response = await record(
                cardDelete,
                "providers.masterpass.deleteCard",
                CodeSamples.deleteCard(accountKey, card.alias),
                .object(["accountKey": .string(accountKey), "cardAlias": .string(card.alias)])
            ) { await PaywallSdk.providers.masterpass.deleteCard(DeleteCardParams(accountKey: accountKey, cardAlias: card.alias)) }
            if response.status == .success {
                cardDelete.success = true
                // The card list is refreshed automatically after a delete.
                await runAccountAccess()
            } else {
                cardDelete.error = response.message ?? "Delete card failed"
            }
        }
    }

    /// "Kart Kaydet".
    func addCardToMasterpass() {
        if !isProviderAndSessionReady { addCard.error = "Provider and session must be ready first"; return }
        if userPhone.isBlankText { addCard.error = "UserPhone (accountKey) is required"; return }
        if userId.isBlankText { addCard.error = "userId is required"; return }
        if !cardFieldsFilled { addCard.error = "All card fields are required"; return }
        if cardAlias.isBlankText { addCard.error = "Card Alias is required"; return }

        launch(addCard) { [self] in
            let params = AddCardParams(
                userId: userId.trimmingCharacters(in: .whitespaces),
                accountKey: userPhone,
                accountAliasName: cardAlias.trimmingCharacters(in: .whitespaces),
                cardHolderName: cardHolderName,
                cardNumber: cardNumber.input,
                expiryDate: expiryMonth + expiryYear,
                cvv: cvv.cvvInput!,
                termsConsent: terms.input,
                requestReferenceNumber: Self.numericReference(),
                accountKeyType: .msisdn
            )
            let response = await record(
                addCard,
                "providers.masterpass.addCard",
                CodeSamples.addCard(params.userId, params.accountKey, params.accountAliasName, cardHolderName, params.expiryDate, params.requestReferenceNumber),
                cardRequest([
                    "userId": .string(params.userId),
                    "accountKey": .string(params.accountKey),
                    "accountAliasName": .string(params.accountAliasName),
                    "requestReferenceNumber": .string(params.requestReferenceNumber),
                    "termsConsent": .bool(terms.isChecked),
                ])
            ) { await PaywallSdk.providers.masterpass.addCard(params) }

            if openOtpIfRequired(response, "addCard") { return }
            switch response.status {
            case .success:
                addCard.success = true
            case .actionRequired:
                if let url = response.data?.redirectUrl { offerThreeD(url, nil, nil) }
                addCard.error = "3D Secure required. URL: \(response.data?.redirectUrl ?? "N/A")"
            case .failed:
                addCard.error = response.message ?? "Add card failed"
            }
        }
    }

    // ========== C) PAYMENT TEST AREA ==========

    func payWithRegisteredCard() {
        let action = registeredPayment
        guard isProviderAndSessionReady else { action.error = "Provider and Session must be ready first"; return }
        guard !cards.isEmpty else { action.error = "No registered cards available. Please get card list first."; return }
        guard let card = selectedCard else { action.error = "Please select a registered card"; return }
        guard !card.alias.isBlankText else { action.error = "Card alias is missing"; return }
        guard !card.bin.isBlankText else { action.error = "Card BIN is missing"; return }
        guard let sessionId else { action.error = "SessionId not found"; return }
        guard let detail = paymentDetail(action) else { return }

        launch(action) { [self] in
            let params = PaymentInitParams(
                paymentSource: .registeredCard,
                paymentDetail: detail,
                cardData: PaymentCardData(cardAlias: card.alias),
                products: sdkProducts(),
                sessionId: sessionId,
                // The alias is sent as ownerName for registered cards.
                card: PaymentInitCard(cardBin: card.bin, cardMasked: card.masked, ownerName: card.alias),
                customer: customer()
            )
            let name = "payment.initPayment (REGISTERED_CARD)"
            let response = await record(
                action,
                name,
                CodeSamples.paymentRegistered(card.alias, card.bin, card.masked, detail),
                paymentRequest(detail, [
                    "paymentSource": .string("REGISTERED_CARD"),
                    "cardAlias": .string(card.alias),
                    "cardBin": .string(card.bin),
                ])
            ) { await PaywallSdk.payment.initPayment(params) }
            handlePayment(action, name, response, detail)
        }
    }

    func payWithManualCard() {
        let action = manualPayment
        guard isProviderAndSessionReady else { action.error = "Provider and Session must be ready first"; return }
        guard sessionId != nil else { action.error = "SessionId not found"; return }
        guard !userPhone.isBlankText else { action.error = "UserPhone (accountKey) is required for registerAndPurchase"; return }
        guard !userId.isBlankText else { action.error = "UserId is required for registerAndPurchase"; return }
        guard cardFieldsFilled else { action.error = "All card fields are required"; return }
        if saveCardOnPayment && cardAlias.isBlankText { action.error = "Card Alias is required when saving card"; return }
        guard let detail = paymentDetail(action) else { return }
        if saveCardOnPayment { registerAndPurchase(detail) } else { manualPaymentInit(detail) }
    }

    private func manualPaymentInit(_ detail: PaymentDetail) {
        launch(manualPayment) { [self] in
            let params = PaymentInitParams(
                paymentSource: .manualCard,
                paymentDetail: detail,
                cardData: PaymentCardData(
                    cardNumber: cardNumber.input,
                    ownerName: cardHolderName,
                    expiryDate: expiryMonth + expiryYear,
                    cvv: cvv.cvvInput
                ),
                products: sdkProducts(),
                sessionId: sessionId,
                customer: customer()
            )
            let name = "payment.initPayment (MANUAL_CARD)"
            let response = await record(
                manualPayment,
                name,
                CodeSamples.paymentManual(cardHolderName, expiryMonth + expiryYear, detail),
                paymentRequest(detail, ["paymentSource": .string("MANUAL_CARD"), "cardData": cardRequest([:])])
            ) { await PaywallSdk.payment.initPayment(params) }
            handlePayment(manualPayment, name, response, detail)
        }
    }

    private func registerAndPurchase(_ detail: PaymentDetail) {
        launch(manualPayment) { [self] in
            let alias = cardAlias.trimmingCharacters(in: .whitespaces)
            let params = RegisterAndPurchaseParams(
                accountKey: userPhone,
                merchantUserId: userId.trimmingCharacters(in: .whitespaces),
                paymentDetail: detail,
                cardData: RegisterCardData(
                    cardNumber: cardNumber.input,
                    cardHolderName: cardHolderName,
                    expiryDate: expiryMonth + expiryYear,
                    cvv: cvv.cvvInput!,
                    cardAlias: alias
                ),
                termsConsent: terms.input,
                products: sdkProducts(),
                sessionId: sessionId,
                accountKeyType: .msisdn,
                customer: customer(),
                // registerAndPurchase is sent with force3D: true.
                force3D: true
            )
            let response = await record(
                manualPayment,
                "payment.registerAndPurchase",
                CodeSamples.registerAndPurchase(params.accountKey, params.merchantUserId, cardHolderName, expiryMonth + expiryYear, alias, detail),
                paymentRequest(detail, [
                    "accountKey": .string(params.accountKey),
                    "accountKeyType": .string("Msisdn"),
                    "merchantUserId": .string(params.merchantUserId),
                    "force3D": .bool(true),
                    "cardData": cardRequest(["cardAlias": .string(alias)]),
                    "termsConsent": .bool(terms.isChecked),
                ])
            ) { await PaywallSdk.payment.registerAndPurchase(params) }
            handlePayment(manualPayment, "payment.registerAndPurchase", response, detail)
        }
    }

    private func handlePayment(
        _ action: ActionState,
        _ name: String,
        _ response: SdkResponse<MasterpassPaymentInitResult>,
        _ detail: PaymentDetail
    ) {
        if openOtpIfRequired(response, name) { return }
        let data = response.data
        if response.actionType == .threeD {
            if let url = data?.redirectUrl { offerThreeD(url, detail.successUrl, detail.failUrl) }
            action.error = "3D Secure required. URL: \(data?.redirectUrl ?? "N/A")"
        } else if response.status == .actionRequired {
            action.error = response.message ?? "Action required"
        } else if response.status == .success {
            action.success = true
        } else {
            action.error = response.message ?? "Payment failed"
        }
    }

    // ========== D) OTP / ACTION FLOW HANDLER ==========

    /// Opens the OTP sheet when a response asks for OTP (payments, accountAccess, merchantLink and addCard).
    private func openOtpIfRequired<T>(_ response: SdkResponse<T>, _ action: String) -> Bool {
        guard response.status == .actionRequired, response.actionType == .bankOtp || response.actionType == .masterpassOtp else {
            return false
        }
        awaitingOtp = true
        pendingAction = action
        otp.clear()
        otpResendMessage = nil
        otpRequest = OtpRequest(
            title: response.actionType == .bankOtp ? "Banka OTP'si" : "Masterpass OTP'si",
            message: response.message ?? "Telefonuna gelen kodu gir.",
            pendingAction: action
        )
        return true
    }

    /// Sends the entered OTP.
    func submitOtp() {
        guard let request = otpRequest else { return }
        otpRequest = nil
        launch(otpVerify) { [self] in
            let response = await record(
                otpVerify,
                "providers.masterpass.verifyOtp",
                CodeSamples.verifyOtp(),
                .object([
                    "otp": .string("\(otp.digitCount) hane (güvenli alan)"),
                    "otpIstenenIslem": .string(request.pendingAction),
                ])
            ) { await PaywallSdk.providers.masterpass.verifyOtp(VerifyOtpParams(otp: otp.otpInput!)) }
            otp.clear()
            let data = response.data
            if response.status == .success {
                if pendingAction == "merchantLink" { linkedState = true }
                resetOtp()
                otpVerify.success = true
                // Nothing is triggered automatically; the user presses the button again.
            } else if response.status == .actionRequired, response.actionType == .bankOtp || response.actionType == .masterpassOtp {
                // Chained OTP (e.g. 5008 -> 5001): the sheet opens again.
                _ = openOtpIfRequired(response, request.pendingAction)
            } else if response.status == .actionRequired, response.actionType == .threeD {
                resetOtp()
                if let url = data?.redirectUrl { offerThreeD(url, data?.successUrl, data?.failUrl) }
                otpVerify.error = "3D Secure required. URL: \(data?.redirectUrl ?? "N/A")"
            } else {
                otpVerify.error = response.message ?? "OTP verification failed"
                resetOtp()
            }
        }
    }

    func cancelOtp() {
        otpRequest = nil
        resetOtp()
    }

    func resendOtp() {
        otpResendMessage = nil
        otpResendLoading = true
        let task = Task { [self] in
            defer { otpResendLoading = false }
            let response = await record(nil, "providers.masterpass.resendOtp", CodeSamples.resendOtp(), .object([:])) {
                await PaywallSdk.providers.masterpass.resendOtp()
            }
            otpResendMessage = response.success ? "OTP tekrar gönderildi. Lütfen yeni kodu girin." : (response.message ?? "OTP tekrar gönderilemedi.")
        }
        tasks.append(task)
    }

    private func resetOtp() {
        awaitingOtp = false
        pendingAction = nil
    }

    private func offerThreeD(_ url: String, _ success: String?, _ fail: String?) {
        guard let parsed = URL(string: url) else { return }
        threeD = ThreeDRequest(url: parsed, successUrl: success, failUrl: fail)
    }

    func onThreeDFinished(_ result: String, lastUrl: String) {
        threeDOpen = nil
        addStep("3D", error: "\(result)\n\(lastUrl)")
    }

    // ========== DEBUG ==========

    func clearLogs() { logs = [] }

    func logsAsJSON() -> String {
        let steps: [PaywallJSON] = logs.enumerated().map { index, step in
            var object: [String: PaywallJSON] = [
                "step": .number(String(index + 1)),
                "timestamp": .string(ISO8601DateFormatter().string(from: step.startedAt)),
                "durationMs": .number(String(Int(step.endedAt.timeIntervalSince(step.startedAt) * 1000))),
                "actionName": .string(step.actionName),
            ]
            if let value = step.request { object["request"] = value }
            if let value = step.response { object["response"] = value }
            if let value = step.normalized { object["normalizedResult"] = value }
            if let guidance = step.guidance {
                object["neYapilmali"] = .object([
                    "baslik": .string(guidance.title),
                    "anlami": .string(guidance.meaning),
                    "adimlar": .array(guidance.nextSteps.map(PaywallJSON.string)),
                ])
            }
            if let value = step.code { object["merchantKodu"] = .string(value) }
            if let value = step.error { object["error"] = .string(value) }
            return .object(object)
        }
        return PaywallJSON.array(steps).jsonString(pretty: true)
    }

    func addProduct() {
        products.append(ProductRow("PRODUCT-\(products.count + 1)", "New Product", "1", "0", "0"))
    }

    func removeProduct(_ product: ProductRow) {
        products.removeAll { $0.id == product.id }
        updatePaymentAmountFromProducts()
    }

    func updatePaymentAmountFromProducts() {
        paymentAmount = NSDecimalNumber(decimal: productTotal).stringValue
    }

    // ========== helpers ==========

    private func accountGuards(_ action: ActionState) -> Bool {
        let error: String?
        if awaitingOtp {
            error = "OTP verification required. Please complete OTP verification first."
        } else if !isProviderAndSessionReady {
            error = "Provider and session must be ready first"
        } else if userPhone.isBlankText {
            error = "UserPhone (accountKey) is required"
        } else if userId.isBlankText {
            error = "userId is required for Masterpass account access"
        } else {
            error = nil
        }
        guard let error else { return true }
        action.error = error
        action.success = false
        return false
    }

    private var cardFieldsFilled: Bool {
        cardNumber.digitCount > 0 && !cardHolderName.isBlankText && !expiryMonth.isBlankText && !expiryYear.isBlankText && cvv.digitCount > 0
    }

    /// Amount follows the product total; currencyId 1, clientIp 192.168.1.1, installment 1, new merchant code.
    private func paymentDetail(_ action: ActionState) -> PaymentDetail? {
        if productTotal > 0 { updatePaymentAmountFromProducts() }
        guard let amount = Decimal(string: paymentAmount.replacingOccurrences(of: ",", with: ".")) else {
            action.error = "Amount must be a number"
            return nil
        }
        return PaymentDetail(
            amount: amount,
            currencyId: 1,
            merchantUniqueCode: "MERCHANT-\(Int(Date().timeIntervalSince1970 * 1000))",
            trackingCode: trackingCode,
            successUrl: successUrl,
            failUrl: failUrl,
            clientIp: "192.168.1.1",
            installment: 1
        )
    }

    private func sdkProducts() -> [Product] {
        products.map { Product(productId: $0.code, productName: $0.name, productAmount: $0.total) }
    }

    private func customer() -> Customer {
        Customer(fullName: customerFullName, phone: customerPhone, email: customerEmail, identityNumber: customerIdentityNumber)
    }

    private func paymentRequest(_ detail: PaymentDetail, _ extra: [String: PaywallJSON]) -> PaywallJSON {
        var object = extra
        object["sessionId"] = sessionId.map(PaywallJSON.string) ?? .null
        object["paymentDetail"] = .object([
            "amount": .number(NSDecimalNumber(decimal: detail.amount).stringValue),
            "currencyId": .number(String(detail.currencyId)),
            "merchantUniqueCode": .string(detail.merchantUniqueCode),
            "trackingCode": .string(detail.trackingCode),
            "successUrl": .string(detail.successUrl),
            "failUrl": .string(detail.failUrl),
            "clientIp": .string(detail.clientIp),
            "installment": .number(String(detail.installment)),
        ])
        object["customer"] = .object([
            "fullName": .string(customerFullName),
            "phone": .string(customerPhone),
            "email": .string(customerEmail),
            "identityNumber": .string(customerIdentityNumber),
        ])
        object["products"] = .array(sdkProducts().map {
            .object([
                "productId": .string($0.productId),
                "productName": .string($0.productName),
                "productAmount": .number(NSDecimalNumber(decimal: $0.productAmount).stringValue),
            ])
        })
        return .object(object)
    }

    /// Card values as shown in the log (masked); the app cannot read them anyway.
    private func cardRequest(_ extra: [String: PaywallJSON]) -> PaywallJSON {
        var object = extra
        object["cardNumber"] = .string("\(cardNumber.bin.map { String($0.prefix(4)) } ?? "****") **** **** **** (\(cardNumber.digitCount) hane, güvenli alan)")
        object["cardHolderName"] = .string(cardHolderName)
        object["expiryDate"] = .string(expiryMonth + expiryYear)
        object["cvv"] = .string("***")
        return .object(object)
    }

    /// One SDK call: runs it, keeps the response on the button and adds one card to the "Akış" tab.
    private func record<T>(
        _ action: ActionState?,
        _ name: String,
        _ code: String,
        _ request: PaywallJSON,
        _ call: () async -> SdkResponse<T>
    ) async -> SdkResponse<T> {
        let startedAt = Date()
        let response = await call()
        let guidance = Guide.of(name, response)
        let json = SdkJSON.response(response)
        if let action {
            action.response = json
            action.status = response.status
            action.guidance = guidance
            action.code = code
        }
        logs.append(FlowStep(
            startedAt: startedAt,
            endedAt: Date(),
            actionName: name,
            code: code,
            request: request,
            response: json,
            normalized: SdkJSON.normalized(response),
            guidance: guidance
        ))
        return response
    }

    private func addStep(_ action: String, error: String) {
        let now = Date()
        logs.append(FlowStep(startedAt: now, endedAt: now, actionName: action, error: error))
    }

    /// Runs one button's work with loading state.
    private func launch(_ action: ActionState, _ block: @escaping @MainActor () async -> Void) {
        if action.loading { return }
        action.start()
        let task = Task { @MainActor in
            await block()
            action.loading = false
        }
        tasks.append(task)
    }

    /// 12-digit random numeric reference.
    static func numericReference() -> String { String((0..<12).map { _ in Character(String(Int.random(in: 0...9))) }) }
}

extension String {
    var isBlankText: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
