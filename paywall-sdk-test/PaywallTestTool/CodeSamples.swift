import Foundation
import PaywallSDK

/// "Merchant kodu": the iOS SDK call each button makes, with the values used.
enum CodeSamples {
    private static func q(_ value: String?) -> String {
        guard let value else { return "nil" }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func initPaywallSdk(_ environment: PaywallEnvironment, _ includeMasterpassSession: Bool) -> String {
        """
        // Token: merchant backend'i Paywall'dan alır (SDK token üretmez).
        let response = await PaywallSdk.initPaywallSdk(
            environment: .\(environment.rawValue),
            token: tokenFromMerchantBackend,
            includeMasterpassSession: \(includeMasterpassSession)
        )
        """
    }

    static func providerInit() -> String {
        """
        // initPaywallSdk başarılı olduktan sonra, parametresiz.
        let response = await PaywallSdk.providers.masterpass.initialize()
        """
    }

    static func getCardList(_ accountKey: String, _ userId: String) -> String {
        """
        let response = await PaywallSdk.providers.masterpass.getCardList(
            GetCardListParams(accountKey: \(q(accountKey)), userId: \(q(userId)), accountKeyType: .msisdn)
        )
        """
    }

    static func linkMerchant(_ accountKey: String) -> String {
        "let response = await PaywallSdk.providers.masterpass.linkMerchant(LinkMerchantParams(accountKey: \(q(accountKey))))"
    }

    static func deleteCard(_ accountKey: String, _ alias: String) -> String {
        """
        let response = await PaywallSdk.providers.masterpass.deleteCard(
            DeleteCardParams(accountKey: \(q(accountKey)), cardAlias: \(q(alias)))
        )
        """
    }

    static func addCard(_ userId: String, _ accountKey: String, _ alias: String, _ holder: String, _ expiry: String, _ reference: String) -> String {
        """
        let response = await PaywallSdk.providers.masterpass.addCard(
            AddCardParams(
                userId: \(q(userId)),
                accountKey: \(q(accountKey)),
                accountAliasName: \(q(alias)),
                cardHolderName: \(q(holder)),
                cardNumber: cardNumberState.input,   // PaywallCardNumberFieldView
                expiryDate: \(q(expiry)),               // MMYY
                cvv: cvvState.cvvInput!,             // PaywallSecureTextFieldView (.cvv)
                termsConsent: termsState.input,      // PaywallTermsCheckBoxView
                requestReferenceNumber: \(q(reference))
            )
        )
        """
    }

    static func verifyOtp() -> String {
        """
        let response = await PaywallSdk.providers.masterpass.verifyOtp(
            VerifyOtpParams(otp: otpState.otpInput!)   // PaywallSecureTextFieldView (.otp)
        )
        """
    }

    static func resendOtp() -> String { "let response = await PaywallSdk.providers.masterpass.resendOtp()" }

    private static func detail(_ detail: PaymentDetail) -> String {
        """
                paymentDetail: PaymentDetail(
                    amount: Decimal(string: \(q(NSDecimalNumber(decimal: detail.amount).stringValue)))!,
                    currencyId: \(detail.currencyId),
                    merchantUniqueCode: \(q(detail.merchantUniqueCode)),
                    trackingCode: \(q(detail.trackingCode)),
                    successUrl: \(q(detail.successUrl)),
                    failUrl: \(q(detail.failUrl)),
                    clientIp: \(q(detail.clientIp)),
                    installment: \(detail.installment)
                ),
        """
    }

    static func paymentRegistered(_ alias: String, _ bin: String, _ masked: String, _ paymentDetail: PaymentDetail) -> String {
        """
        let response = await PaywallSdk.payment.initPayment(
            PaymentInitParams(
                paymentSource: .registeredCard,
        \(detail(paymentDetail))
                cardData: PaymentCardData(cardAlias: \(q(alias))),
                products: products,
                card: PaymentInitCard(cardBin: \(q(bin)), cardMasked: \(q(masked)), ownerName: \(q(alias))),
                customer: customer
            )
        )
        """
    }

    static func paymentManual(_ holder: String, _ expiry: String, _ paymentDetail: PaymentDetail) -> String {
        """
        let response = await PaywallSdk.payment.initPayment(
            PaymentInitParams(
                paymentSource: .manualCard,
        \(detail(paymentDetail))
                cardData: PaymentCardData(
                    cardNumber: cardNumberState.input,
                    ownerName: \(q(holder)),
                    expiryDate: \(q(expiry)),
                    cvv: cvvState.cvvInput
                ),
                products: products,
                customer: customer
            )
        )
        """
    }

    static func registerAndPurchase(
        _ accountKey: String,
        _ userId: String,
        _ holder: String,
        _ expiry: String,
        _ alias: String,
        _ paymentDetail: PaymentDetail
    ) -> String {
        """
        let response = await PaywallSdk.payment.registerAndPurchase(
            RegisterAndPurchaseParams(
                accountKey: \(q(accountKey)),
                merchantUserId: \(q(userId)),
        \(detail(paymentDetail))
                cardData: RegisterCardData(
                    cardNumber: cardNumberState.input,
                    cardHolderName: \(q(holder)),
                    expiryDate: \(q(expiry)),
                    cvv: cvvState.cvvInput!,
                    cardAlias: \(q(alias))
                ),
                termsConsent: termsState.input,      // PaywallTermsCheckBoxView
                products: products,
                customer: customer,
                force3D: true
            )
        )
        """
    }

    static let handling = """
    switch response.status {
    case .success:
        break // İşlem tamam: response.data
    case .actionRequired:
        switch response.actionType {
        case .bankOtp, .masterpassOtp: showOtp()                    // sonra verifyOtp(...)
        case .threeD: openWebView(response.data?.redirectUrl)
        case .merchantLinkRequired: linkMerchant()                 // sonra getCardList(...)
        case nil: break
        }
    case .failed:
        showError(response.errorCode, response.message)
    }
    """
}
