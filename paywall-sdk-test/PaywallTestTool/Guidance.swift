import PaywallSDK

enum Tone { case success, action, error }

/// "Ne yapılmalı?": what an SDK response means and what the merchant app does next.
struct Guidance: Hashable {
    let tone: Tone
    let title: String
    let meaning: String
    let nextSteps: [String]
}

enum Guide {
    /// SDK numeric codes (MASTERPASS_ERROR_MAP) -> Masterpass code names, for the descriptions below.
    private static let sdkCodeNames: [String: String] = [
        "4001": "OTP_IS_NOT_VALID",
        "4002": "ACCOUNT_NOT_LINKED_TO_MERCHANT",
        "4003": "USER_NOT_FOUND",
        "4004": "CARD_ALREADY_EXISTS",
        "4005": "MERCHANT_USER_ID_ALREADY_IN_USE",
        "4006": "FRAUD_DETECTED_DUE_TO_REPETITIVE_DELETION",
        "4007": "INVALID_ACCOUNT_KEY_IN_TOKEN",
        "4008": "INVALID_CARD_NUMBER",
        "4009": "INVALID_EXPIRY_DATE",
        "4010": "INVALID_CVV",
        "4011": "MISSING_CARD_ALIAS",
        "4012": "MISSING_CARD_HOLDER_NAME",
    ]

    private static let allCodes: [String: String] = Dictionary(
        GuideData.errorCodeGroups.flatMap(\.codes).map { ($0.code, $0.description) },
        uniquingKeysWith: { first, _ in first }
    )

    static func of<T>(_ function: String, _ response: SdkResponse<T>) -> Guidance {
        switch response.status {
        case .success: return success(function, response)
        case .actionRequired: return actionRequired(response)
        case .failed: return failed(function, response)
        }
    }

    private static func success<T>(_ function: String, _ response: SdkResponse<T>) -> Guidance {
        func ok(_ title: String, _ meaning: String, _ next: String...) -> Guidance {
            Guidance(tone: .success, title: title, meaning: meaning, nextSteps: next)
        }
        if function.hasSuffix("initPaywallSdk") {
            if (response.data as? InitPaywallSdkResult)?.hasMasterpassSession == true {
                return ok(
                    "SDK hazır",
                    "Token Paywall'da doğrulandı; Masterpass session bilgileri (sessionId, token, telefon, userId) SDK'nın içinde.",
                    "PaywallSdk.providers.masterpass.initialize() çağır (test aracı bunu otomatik yapar)."
                )
            }
            return ok(
                "SDK hazır, Masterpass session yok",
                "Token doğrulandı ama Masterpass session gelmedi.",
                "Masterpass işlemleri için includeMasterpassSession: true ile tekrar başlat."
            )
        }
        if function.hasSuffix("masterpass.initialize") {
            return ok(
                "Masterpass hazır",
                "Masterpass SDK session bilgileriyle yapılandırıldı.",
                "providers.masterpass.getCardList ile kullanıcının kayıtlı kartlarını getir."
            )
        }
        if function.hasSuffix("getCardList") {
            let count = (response.data as? GetCardListResult)?.cards?.count ?? 0
            return ok(
                "\(count) kart geldi",
                "Kullanıcının Masterpass hesabı bu merchant'a bağlı.",
                "Kartları kullanıcıya listele.",
                "Kayıtlı kartla ödeme: seçilen kartın cardAlias, maskedCardNumber ve cardBin değerleriyle payment.initPayment / initWithRegisteredCard.",
                "Kart yoksa: yeni kartla ödeme (payment.initPayment .manualCard) veya registerAndPurchase / addCard."
            )
        }
        if function.hasSuffix("linkMerchant") {
            return ok("Hesap merchant'a bağlandı", "Kullanıcının Masterpass hesabı artık bu merchant'ta kullanılabilir.", "getCardList'i tekrar çağır.")
        }
        if function.hasSuffix("verifyOtp") {
            return ok(
                "OTP doğrulandı",
                "Kullanıcının girdiği kod doğru.",
                "OTP bir ödemeye aitse ödeme tamamlandı; SDK sonucu Paywall'a kendisi bildirdi (payment/mark).",
                "OTP bir hesap işlemine aitse (linkMerchant, getCardList, addCard) o işlemi tekrar çağır."
            )
        }
        if function.hasSuffix("resendOtp") {
            return ok("OTP tekrar gönderildi", "Kullanıcıya yeni bir SMS kodu gitti.", "Kullanıcıdan yeni kodu al ve verifyOtp çağır.")
        }
        if function.hasSuffix("addCard") {
            return ok("Kart kaydedildi", "Kart kullanıcının Masterpass hesabına eklendi.", "getCardList ile listeyi yenile.")
        }
        if function.hasSuffix("deleteCard") {
            return ok("Kart silindi", "Kart kullanıcının Masterpass hesabından kaldırıldı.", "getCardList ile listeyi yenile.")
        }
        return ok(
            "Ödeme tamamlandı",
            "Masterpass ödemeyi onayladı (0000). SDK sonucu Paywall'a bildirdi (payment/mark).",
            "Kullanıcıya başarı ekranını göster.",
            "nextActionHint \"Please commit the payment.\": merchant backend'i siparişi tamamlar.",
            "data.paymentId, uniqueCode ve maskedCard raporlama için saklanabilir."
        )
    }

    private static func actionRequired<T>(_ response: SdkResponse<T>) -> Guidance {
        switch response.actionType {
        case .bankOtp?, .masterpassOtp?:
            return Guidance(
                tone: .action,
                title: response.actionType == .bankOtp ? "Banka OTP'si gerekiyor" : "Masterpass OTP'si gerekiyor",
                meaning: "Kullanıcının telefonuna SMS ile tek kullanımlık kod gönderildi.",
                nextSteps: [
                    "PaywallOtpField göster; kullanıcı kodu girince verifyOtp(VerifyOtpParams(otp: otpField.input)) çağır.",
                    "Kod gelmezse resendOtp() çağır.",
                    "Test aracı OTP penceresini otomatik açar.",
                ]
            )
        case .threeD?:
            return Guidance(
                tone: .action,
                title: "3D Secure doğrulaması gerekiyor",
                meaning: "Banka, ödemeyi kendi 3D sayfasında doğrulamak istiyor.",
                nextSteps: [
                    "data.redirectUrl'i WKWebView'da aç (Paywall dönüş adresi returnUrl olarak eklenmiş).",
                    "Kullanıcı bankanın sayfasında doğrular; sonuç Paywall'a gider, merchant kesin sonucu kendi backend'inden öğrenir.",
                    "successUrl / failUrl'e yönlenme, WebView'ı kapatma sinyalidir.",
                ]
            )
        case .merchantLinkRequired?:
            return Guidance(
                tone: .action,
                title: "Hesap bu merchant'a bağlı değil",
                meaning: "Kullanıcının Masterpass hesabı var ama bu merchant'ta henüz kullanılmamış.",
                nextSteps: [
                    "linkMerchant(LinkMerchantParams(accountKey:)) çağır.",
                    "OTP isterse verifyOtp; ardından getCardList'i tekrar çağır.",
                ]
            )
        case nil:
            return Guidance(tone: .action, title: "Aksiyon gerekiyor", meaning: response.message ?? "", nextSteps: [])
        }
    }

    private static func failed<T>(_ function: String, _ response: SdkResponse<T>) -> Guidance {
        let code = response.errorCode ?? ""
        var steps: [String] = []
        let title: String
        let meaning: String
        switch response.source {
        case .sdk:
            title = "İşlem başarısız (\(code))"
            meaning = response.message ?? "Parametre ya da çağrı sırası hatası."
            if let fix = sdkFix(code) { steps.append(fix) }
            if let field = response.field { steps.append("Hatalı alan: \(field)") }
            if let hint = response.actionHint { steps.append(hint) }
        case .paywall:
            title = "Paywall isteği reddetti (\(code))"
            meaning = response.message ?? "Paywall hata kodu: \(code)"
            steps.append("Paywall ekibiyle errorCode (\(code)) üzerinden kontrol et.")
        case .masterpass:
            title = "Masterpass hatası (\(code))"
            let name = sdkCodeNames[code] ?? code
            let action = GuideData.errorActions.first { $0.code == name }
            meaning = action?.meaning ?? allCodes[name] ?? response.message ?? "Masterpass hata kodu: \(code)"
            if let action { steps += action.actions }
            if code == "MASTERPASS_ERROR" {
                steps.append("Masterpass'a ulaşılamadı ya da cevap çözülemedi; bağlantıyı kontrol edip tekrar dene.")
            } else if code == "MASTERPASS_TIMEOUT" {
                steps.append("Masterpass zamanında cevap vermedi; ödemenin sonucu belirsiz. "
                    + "Tekrar denemeden önce ödemenin durumunu Paywall'dan sorgula.")
            } else if code == "SDK_ERROR" {
                steps.append("Beklenmeyen hata. message alanına bak.")
            }
            if let message = response.message, message != meaning { steps.append("SDK mesajı: \(message)") }
        }
        if function.hasPrefix("payment.") && response.source != .sdk {
            steps.append("SDK ödemeyi Paywall'a başarısız olarak bildirdi (payment/mark); kullanıcıya hata göster, tekrar deneyebilirsin.")
        }
        return Guidance(tone: .error, title: title, meaning: meaning, nextSteps: steps)
    }

    private static func sdkFix(_ code: String) -> String? {
        switch code {
        case "INIT_WITH_MASTERPASS_TOKEN_ERROR", "VERIFY_RESPONSE_INVALID":
            return "Paywall token'ı doğrulamadı. Token geçersiz ya da süresi dolmuş olabilir veya ortam (DEV / TEST / PROD) "
                + "token'ın ortamıyla aynı değil. Merchant backend'inden yeni token al. Ayrıntı Akış → ③ istekte."
        case "MASTERPASS_OBJECT_NULL":
            return "Paywall Masterpass session bilgisi dönmedi; token Masterpass session'ı içermiyor (backend'e sor)."
        case "MISSING_INCLUDE_MASTERPASS_SESSION": return "includeMasterpassSession: true ile çağır."
        case "INVALID_ENVIRONMENT": return "Geçerli bir ortam seç (DEV / TEST / PROD)."
        case "SDK_NOT_INITIALIZED": return "Önce PaywallSdk.initPaywallSdk çağır."
        case "SESSION_NOT_STARTED", "MISSING_TOKEN", "INVALID_SESSION":
            return "initPaywallSdk'yı includeMasterpassSession: true ve geçerli bir token ile çağır."
        case "PROVIDER_NOT_INITIALIZED": return "Önce PaywallSdk.providers.masterpass.initialize() çağır."
        case "SESSION_EXPIRED": return "Session süresi doldu: merchant backend'inden yeni token al, initPaywallSdk'yı tekrar çağır."
        case "SDK_NOT_LOADED": return "Masterpass hazırlanamadı (ör. jailbreak'li cihaz, eksik session bilgisi)."
        case "TERMS_NOT_ACCEPTED": return "Kullanıcı Masterpass koşul onay kutusunu işaretlemeli (kart kaydı için zorunlu)."
        case "MISSING_OTP_CODE", "OTP_IS_NOT_VALID": return "Kullanıcıdan OTP'yi tekrar iste."
        default:
            return code.hasPrefix("MISSING_") || code.hasPrefix("INVALID_") ? "İlgili alanı düzeltip tekrar dene." : nil
        }
    }
}
