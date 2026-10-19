## Tanıtım

Bu repository iki ana bileşenden oluşmaktadır:

- **public-sdk**: Paywall iOS SDK'nın derlenmiş dağıtım paketini (`PaywallSDK.xcframework`, `Masterpass.xcframework`)
  içerir. Merchant'lar SDK'yı bu repoyu Swift Package Manager ile ekleyerek kurar (bkz. [Kurulum](#kurulum)).
- **paywall-sdk-test**: SDK'nın tüm fonksiyonlarını cihazda veya simülatörde deneyen iOS test uygulamasıdır. SDK'yı
  bu repodaki paketten kullanır; her çağrıda giden istekleri ve SDK'nın döndüğü cevabı gösterir. Xcode ile
  `paywall-sdk-test/PaywallTestTool.xcodeproj` açılarak ya da `cd paywall-sdk-test && ./run.sh` komutuyla çalıştırılır.

# Paywall iOS SDK

Paywall ödeme altyapısı için iOS SDK. Masterpass ile kayıtlı kartla ödeme, yeni kartla ödeme, kart kaydetme ve kart
yönetimi akışlarını sunar. Swift ile yazılmıştır; Masterpass iOS SDK paketin içinde gelir, ayrıca eklenmez.

## Kurulum

### Swift Package Manager

SDK, [PaywallSdk_iOS_Public](https://github.com/paywallone/PaywallSdk_iOS_Public) reposunda derlenmiş
(`xcframework`) olarak yayınlanır. Xcode'da **File > Add Package Dependencies…** ile repo adresini girin
(`https://github.com/paywallone/PaywallSdk_iOS_Public`) ve uygulama hedefinize `PaywallSDK` ürününü bağlayın.
`Package.swift` kullanıyorsanız:

```swift
dependencies: [
    .package(url: "https://github.com/paywallone/PaywallSdk_iOS_Public", from: "1.0.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "PaywallSDK", package: "PaywallSdk_iOS_Public")]),
]
```

**Gereksinimler:** iOS 13.0+, Xcode 26.2+.

> Masterpass SDK'yı uygulamanıza **ayrıca eklemeyin**; Paywall SDK'nın içinde gelir.

### Import

```swift
import PaywallSDK
```

## Kullanım Adımları

### Adım 1: Geçici Token Alın

Merchant backend'iniz Paywall API'den geçici bir token alır ve uygulamanıza iletir. Token, Masterpass session
bilgilerini (session id, kullanıcı id, telefon) içerir. SDK token üretmez.

Detaylı bilgi için: [Paywall Yetkilendirme Dokümantasyonu](https://developer.paywall.one/client-side-servisler/yetkilendirme)

```swift
// Örnek: kendi backend'inizden token alın. Bu fonksiyon tamamen sizin backend yapınıza göredir.
func getTokenFromBackend() async throws -> String {
    let (data, _) = try await URLSession.shared.data(from: URL(string: "https://your-backend.com/paywall/token")!)
    return try JSONDecoder().decode(TokenResponse.self, from: data).token
}
```

**⚠️ Önemli:** Session oluşturma **merchant backend** tarafından yapılmalıdır.

### Adım 2: Paywall SDK'yı Initialize Edin

**📚 Dokümantasyon:** https://developer.paywall.one/client-side-servisler/2.-yetkilendirme-sdk

```swift
let token = try await getTokenFromBackend()

let result = await PaywallSdk.initPaywallSdk(
    environment: .dev,                 // .dev | .test | .prod
    token: token,
    includeMasterpassSession: true
)

if result.status == .success, result.data?.hasMasterpassSession == true {
    // Session bilgileri otomatik gelir
    let sessionId = result.data?.body?.masterpass?.sessionId
    print("SDK + Session ready:", sessionId ?? "-")
} else {
    print("SDK initialization failed:", result.message ?? "")
}
```

**✅ Avantajlar:**
- Session bilgileri otomatik olarak SDK'da hazır
- SessionId, userId, userPhone'u elle saklamanıza gerek yok
- Tek adımda SDK + Session hazır

### Adım 3: Masterpass Provider'ı Initialize Edin

```swift
let provider = await PaywallSdk.providers.masterpass.initialize()

if provider.status == .success {
    print("Masterpass provider initialized")
} else {
    print("Provider init failed:", provider.message ?? "")
}
```

**💡 Not:** Gerekli tüm bilgiler (Masterpass token, merchant id) session'dan otomatik alınır; parametre verilmez.

### Adım 4: Ödeme İşlemini Başlatın

Kayıtlı kartla ödeme (kart bilgileri `getCardList` sonucundan gelir):

```swift
let response = await PaywallSdk.payment.initPayment(PaymentInitParams(
    paymentSource: .registeredCard,                  // veya .manualCard
    paymentDetail: PaymentDetail(
        amount: 100.00,
        currencyId: 949,                             // TRY
        merchantUniqueCode: "ORDER-\(Date().timeIntervalSince1970)",
        trackingCode: "TRACK-\(Date().timeIntervalSince1970)",
        successUrl: "https://yoursite.com/success",
        failUrl: "https://yoursite.com/fail",
        clientIp: "192.168.1.1",
        installment: 1
    ),
    cardData: PaymentCardData(cardAlias: "MyCard"),  // Masterpass'a giden kart bilgisi
    products: [Product(productId: "PROD-001", productName: "Product 1", productAmount: 100.00)],
    card: PaymentInitCard(                           // Paywall'a giden maskeli kart bilgisi
        cardBin: "54066700",
        cardMasked: "540667******0001",
        ownerName: "John Doe",
        cardAlias: "MyCard"
    )
))

switch response.status {
case .success:
    print("Payment successful:", response.data?.paymentId ?? 0)
case .actionRequired:
    if response.actionType == .threeD, let url = response.data?.redirectUrl {
        open3DSecure(url)                            // bkz. "3D Secure"
    } else if response.actionType == .bankOtp || response.actionType == .masterpassOtp {
        showOtpScreen()                              // bkz. "OTP Doğrulama"
    }
case .failed:
    print("Payment failed:", response.errorCode ?? "", response.message ?? "")
}
```

## Güvenli Kart Alanları

Kart numarası, CVV ve OTP **yalnızca Paywall güvenli alanlarıyla** alınır. Değer Masterpass tarafından tutulur ve
şifrelenir; uygulamanız da Paywall da okuyamaz. SDK fonksiyonlarına alanın kendisi değil, `input` "handle"'ı verilir.
Handle'dan yalnızca BIN, hane sayısı ve geçerlilik okunabilir.

| Alan | UIKit | SwiftUI |
|---|---|---|
| Kart numarası | `PaywallCardNumberField` | `PaywallCardNumberState` + `PaywallCardNumberFieldView` |
| CVV | `PaywallCvvField` | `PaywallSecureTextState(kind: .cvv)` + `PaywallSecureTextFieldView` |
| OTP | `PaywallOtpField` | `PaywallSecureTextState(kind: .otp)` + `PaywallSecureTextFieldView` |
| Masterpass koşul onayı | `PaywallTermsCheckBox` | `PaywallTermsState` + `PaywallTermsCheckBoxView` |

### UIKit

```swift
let cardNumberField = PaywallCardNumberField()
cardNumberField.placeholder = "Kart numarası"
cardNumberField.font = .systemFont(ofSize: 17)
cardNumberField.borderStyle = .roundedRect
cardNumberField.onBinChanged = { bin in print("BIN:", bin ?? "-") }   // ilk 8 hane

let cvvField = PaywallCvvField()
let otpField = PaywallOtpField()                     // SMS'ten otomatik doldurmayı destekler
let termsCheckBox = PaywallTermsCheckBox()
termsCheckBox.titleText = "Masterpass kullanım koşullarını kabul ediyorum"

// SDK'ya: cardNumberField.input, cvvField.input, otpField.input, termsCheckBox.input
print(cardNumberField.digitCount, cardNumberField.isValid, cvvField.isValid)
```

### SwiftUI

```swift
struct CardForm: View {
    @StateObject private var cardNumber = PaywallCardNumberState()
    @StateObject private var cvv = PaywallSecureTextState(kind: .cvv)
    @StateObject private var terms = PaywallTermsState(titleText: "Masterpass kullanım koşullarını kabul ediyorum")

    var body: some View {
        VStack {
            PaywallCardNumberFieldView(state: cardNumber, placeholder: "Kart numarası") { field in
                field.font = .systemFont(ofSize: 17)      // stil
                field.borderStyle = .roundedRect
            }
            .frame(height: 44)
            Text("BIN: \(cardNumber.bin ?? "-") · \(cardNumber.digitCount) hane")
            PaywallSecureTextFieldView(state: cvv, placeholder: "CVV").frame(height: 44)
            PaywallTermsCheckBoxView(state: terms)
        }
    }
}
// SDK'ya: cardNumber.input, cvv.cvvInput!, terms.input  (OTP: otp.otpInput!)
```

**Stil özellikleri:** `placeholder`, `attributedPlaceholder`, `font`, `textColor`, `textAlignment`, `borderStyle`,
`fieldBackgroundColor`, `keyboardAppearance`, `returnKeyType`, `fieldInputAccessoryView`, `leftView` / `leftViewMode`,
`rightView` / `rightViewMode`. Alanın içindeki metne erişim yoktur; kopyala / kes / yapıştır menüsü kapalıdır.

**💡 Not:** Masterpass koşul onayı yalnızca kullanıcının dokunuşuyla işaretlenir; kart kaydeden işlemlerde
(`addCard`, `registerAndPurchase`) zorunludur.

## Diğer Önemli Fonksiyonlar

### Kayıtlı Kartları Listeleme

**⚠️ Önemli:** `getCardList` arka planda Masterpass'ın `accountAccess` servisini çağırır. Hem kullanıcının
merchant'a bağlı olup olmadığını kontrol eder, hem de kayıtlı kartları listeler.

```swift
let response = await PaywallSdk.providers.masterpass.getCardList(GetCardListParams(
    accountKey: "905437892802",
    userId: "USER_123",
    accountKeyType: .msisdn
))

switch (response.status, response.actionType) {
case (.success, _):
    for card in response.data?.cards ?? [] {
        print(card.cardAlias ?? "", card.maskedCardNumber ?? "", card.cardBin ?? "")
    }
case (.actionRequired, .merchantLinkRequired?):
    print("User not linked to merchant")             // önce linkMerchant
case (.actionRequired, .masterpassOtp?):
    showOtpScreen()                                  // verifyOtp, sonra tekrar getCardList
default:
    print("Get card list failed:", response.message ?? "")
}
```

### Merchant Link (Kullanıcıyı Merchant'a Bağlama)

Masterpass hesabı olan ama bu merchant'ta henüz kullanılmamış kullanıcılar için:

```swift
let response = await PaywallSdk.providers.masterpass.linkMerchant(LinkMerchantParams(accountKey: "905437892802"))

if response.status == .actionRequired {
    showOtpScreen()                                  // OTP doğrulandıktan sonra hesap bağlanır
} else if response.status == .success {
    print("Merchant link successful")
} else {
    print("Merchant link failed:", response.message ?? "")
}
```

### Merchant Link + Kart Listesi Akışı

```swift
func ensureMerchantLinkAndGetCards() async -> [MasterpassCard] {
    let params = GetCardListParams(accountKey: "905437892802", userId: "USER_123")
    var cards = await PaywallSdk.providers.masterpass.getCardList(params)

    if cards.actionType == .merchantLinkRequired {
        let link = await PaywallSdk.providers.masterpass.linkMerchant(LinkMerchantParams(accountKey: "905437892802"))
        if link.status == .actionRequired {
            let otp = await askUserForOtp()           // PaywallOtpField ile kod girilir
            _ = await PaywallSdk.providers.masterpass.verifyOtp(VerifyOtpParams(otp: otp))
        }
        cards = await PaywallSdk.providers.masterpass.getCardList(params)
    }
    return cards.data?.cards ?? []
}
```

### OTP Doğrulama

Bir işlem `ACTION_REQUIRED` + `.bankOtp` / `.masterpassOtp` dönerse kullanıcıdan OTP alınır:

```swift
let otpField = PaywallOtpField()                     // OTP ekranınızda gösterin

let verify = await PaywallSdk.providers.masterpass.verifyOtp(VerifyOtpParams(otp: otpField.input))

switch (verify.status, verify.actionType) {
case (.success, _):
    print("OTP verified")                            // ödeme OTP'si ise ödeme tamamlandı
case (.actionRequired, .threeD?):
    open3DSecure(verify.data?.redirectUrl ?? "")     // OTP sonrası banka 3D isteyebilir
case (.actionRequired, _):
    print("Yeni OTP gerekiyor")                      // .bankOtp / .masterpassOtp
case (.failed, _) where verify.errorCode == SdkErrorCodes.OTP_IS_NOT_VALID:
    print("Kod hatalı, tekrar deneyin")
default:
    print("OTP failed:", verify.message ?? "")
}

// Kod gelmediyse:
let resend = await PaywallSdk.providers.masterpass.resendOtp()
```

**💡 Not:** OTP bir ödemeye aitse SDK sonucu Paywall'a kendisi bildirir; ayrıca bir şey yapmanız gerekmez.

### Kart Ekleme

```swift
let response = await PaywallSdk.providers.masterpass.addCard(AddCardParams(
    userId: "USER_123",
    accountKey: "905437892802",
    accountAliasName: "My Card",
    cardHolderName: "John Doe",
    cardNumber: cardNumberField.input,               // PaywallCardNumberField
    expiryDate: "1226",                              // MMYY (Aralık 2026)
    cvv: cvvField.input,                             // PaywallCvvField
    termsConsent: termsCheckBox.input,               // PaywallTermsCheckBox (işaretli olmalı)
    requestReferenceNumber: "111111111111",          // benzersiz referans
    accountKeyType: .msisdn
))

switch response.status {
case .success: print("Card added:", response.data?.cardAlias ?? "")
case .actionRequired:
    if response.actionType == .threeD { open3DSecure(response.data?.redirectUrl ?? "") } else { showOtpScreen() }
case .failed: print("Add card failed:", response.message ?? "")
}
```

### Kart Silme

```swift
let response = await PaywallSdk.providers.masterpass.deleteCard(DeleteCardParams(
    accountKey: "905437892802",
    cardAlias: "My Card"
))

if response.status == .success {
    print("Card deleted successfully")
} else {
    print("Delete card failed:", response.message ?? "")
}
```

### Yeni Kartla Ödeme

```swift
let response = await PaywallSdk.payment.initPayment(PaymentInitParams(
    paymentSource: .manualCard,
    paymentDetail: paymentDetail,
    cardData: PaymentCardData(
        cardNumber: cardNumberField.input,
        cardHolderName: "John Doe",
        expiryDate: "1226",                          // MMYY
        cvv: cvvField.input
    ),
    products: products,
    customer: Customer(fullName: "John Doe", email: "john@example.com")
))
```

### Kayıtlı Kartla Ödeme (Kısa Yol)

`initPayment(.registeredCard)` ile aynı işi yapar; değerler `getCardList` sonucundaki karttan gelir:

```swift
let card = cards[0]
let response = await PaywallSdk.payment.initWithRegisteredCard(RegisteredCardPaymentParams(
    alias: card.cardAlias ?? "",
    maskedCard: card.maskedCardNumber ?? "",
    cardBin: card.cardBin ?? "",
    cardHolderName: "John Doe",
    paymentDetail: paymentDetail,
    products: products
))
```

### Register and Purchase (Kart Kaydet ve Öde)

Tek seferde hem kart kaydı hem ödeme:

```swift
let response = await PaywallSdk.payment.registerAndPurchase(RegisterAndPurchaseParams(
    accountKey: "905437892802",
    merchantUserId: "USER_123",
    paymentDetail: paymentDetail,
    cardData: RegisterCardData(
        cardNumber: cardNumberField.input,
        cardHolderName: "John Doe",
        expiryDate: "1226",                          // MMYY
        cvv: cvvField.input,
        cardAlias: "My Card"                         // ZORUNLU
    ),
    termsConsent: termsCheckBox.input,               // ZORUNLU (işaretli olmalı)
    products: products,
    customer: Customer(fullName: "John Doe", phone: "905437892802", email: "john@example.com")
))
// Sonuç initPayment ile aynı şekilde işlenir (SUCCESS / OTP / 3D / FAILED).
```

### 3D Secure

`ACTION_REQUIRED` + `.threeD` döndüğünde `data.redirectUrl` bir `WKWebView`'da açılır. URL'e Paywall'ın dönüş adresi
eklenmiştir; sonuç Paywall'a gider. Sayfa `successUrl` veya `failUrl`'inize yönlendiğinde WebView'ı kapatın. Ödemenin
kesin sonucunu kendi backend'inizden öğrenin.

```swift
final class ThreeDViewController: UIViewController, WKNavigationDelegate {
    var redirectUrl: URL!
    var successUrl = "https://yoursite.com/success"
    var failUrl = "https://yoursite.com/fail"
    private let webView = WKWebView()

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.frame = view.bounds
        webView.navigationDelegate = self
        view.addSubview(webView)
        webView.load(URLRequest(url: redirectUrl))
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url?.absoluteString ?? ""
        if url.hasPrefix(successUrl) || url.hasPrefix(failUrl) {
            decisionHandler(.cancel)
            dismiss(animated: true)                  // sonucu backend'inizden sorgulayın
            return
        }
        decisionHandler(.allow)
    }
}
```

## Tam Örnek

```swift
func completePaymentFlow() async {
    do {
        // 1. Backend'den token al (içinde Masterpass session var)
        let token = try await getTokenFromBackend()

        // 2. SDK + Session
        let initResult = await PaywallSdk.initPaywallSdk(environment: .dev, token: token, includeMasterpassSession: true)
        guard initResult.status == .success, initResult.data?.hasMasterpassSession == true else { return }

        // 3. Provider
        guard await PaywallSdk.providers.masterpass.initialize().status == .success else { return }

        // 4. Kartları listele (merchant link kontrolü dahil)
        let cards = await ensureMerchantLinkAndGetCards()
        guard let card = cards.first else { return }

        // 5. Ödeme
        let payment = await PaywallSdk.payment.initWithRegisteredCard(RegisteredCardPaymentParams(
            alias: card.cardAlias ?? "",
            maskedCard: card.maskedCardNumber ?? "",
            cardBin: card.cardBin ?? "",
            cardHolderName: "John Doe",
            paymentDetail: PaymentDetail(
                amount: 100.00, currencyId: 949,
                merchantUniqueCode: "ORDER-1", trackingCode: "TRACK-1",
                successUrl: "https://yoursite.com/success", failUrl: "https://yoursite.com/fail",
                clientIp: "192.168.1.1", installment: 1
            ),
            products: [Product(productId: "PROD-001", productName: "Product 1", productAmount: 100.00)]
        ))

        // 6. Sonuç
        switch payment.status {
        case .success: print("Payment completed successfully")
        case .actionRequired where payment.actionType == .threeD: open3DSecure(payment.data?.redirectUrl ?? "")
        case .actionRequired: showOtpScreen()
        case .failed: print("Payment failed:", payment.errorCode ?? "", payment.message ?? "")
        }
    } catch {
        print("Token error:", error)
    }
}
```

## API Referansı

Tüm fonksiyonlar `async`'tir, herhangi bir thread'den çağrılabilir ve **hata fırlatmaz**: her durumda
`SdkResponse<T>` döner (bkz. "Response Formatları").

### `PaywallSdk.initPaywallSdk(environment:token:includeMasterpassSession:)`

**📚 Dokümantasyon:** https://developer.paywall.one/client-side-servisler/2.-yetkilendirme-sdk

SDK'yı başlatır; token'ı Paywall'da doğrular ve Masterpass session bilgilerini alır.

| Parametre | Tip | Açıklama |
|---|---|---|
| `environment` | `PaywallEnvironment` | `.dev` / `.test` / `.prod` |
| `token` | `String` | Merchant backend'inden gelen geçici token |
| `includeMasterpassSession` | `Bool` | Masterpass işlemleri için `true` |

**Dönüş:** `InitPaywallSdkResult` — `sdkInitialized`, `hasMasterpassSession`, `body` (`masterpass.sessionId`,
`userId`, `userPhone` …).

Tekrar çağrılırsa SDK sıfırlanır; ardından `providers.masterpass.initialize()` de tekrar çağrılmalıdır.

### `PaywallSdk.providers.masterpass.initialize()`

Masterpass provider'ı başlatır. Parametre almaz. **Dönüş:** `MasterpassProviderInitResult` (`masterpassSdkInitialized`).

### `PaywallSdk.providers.masterpass.getCardList(_:)`

Kayıtlı kartları listeler; merchant bağlantısını da kontrol eder.

| Parametre (`GetCardListParams`) | Tip | Açıklama |
|---|---|---|
| `accountKey` | `String` | Telefon numarası (ör. `905437892802`) |
| `userId` | `String` | Merchant kullanıcı ID'si (ZORUNLU) |
| `accountKeyType` | `AccountKeyType` | `.msisdn` (varsayılan) / `.userId` |

**Dönüş:** `GetCardListResult` — `cards: [MasterpassCard]` (`cardAlias`, `maskedCardNumber`, `cardBin`, `cardType`,
`productName`, `isDefaultCard`, `isExpired`, `raw` …), `accountInformation`.

**Olası sonuçlar:**
- `SUCCESS`: kartlar geldi (liste boş olabilir).
- `ACTION_REQUIRED` + `.merchantLinkRequired`: önce `linkMerchant`, sonra tekrar `getCardList`.
- `ACTION_REQUIRED` + `.masterpassOtp`: `verifyOtp`, sonra tekrar `getCardList`.
- `FAILED`: ör. `ACCOUNT_NOT_FOUND` (kullanıcının Masterpass hesabı yok; ilk kart kaydıyla oluşur), `USER_NOT_FOUND`.

### `PaywallSdk.providers.masterpass.linkMerchant(_:)`

Kullanıcının Masterpass hesabını merchant'a bağlar.

| Parametre (`LinkMerchantParams`) | Tip | Açıklama |
|---|---|---|
| `accountKey` | `String` | Telefon numarası |

**Olası sonuçlar:** `SUCCESS` (bağlandı) · `ACTION_REQUIRED` + `.masterpassOtp` / `.bankOtp` (`verifyOtp`) · `FAILED`.

### `PaywallSdk.providers.masterpass.verifyOtp(_:)`

OTP kodunu doğrular.

| Parametre (`VerifyOtpParams`) | Tip | Açıklama |
|---|---|---|
| `otp` | `OtpInput` | `PaywallOtpField.input` veya `PaywallSecureTextState.otpInput` |

**Olası sonuçlar:**
- `SUCCESS`: OTP doğrulandı. Ödeme OTP'si ise SDK Paywall'a ödemeyi başarılı olarak bildirir.
- `ACTION_REQUIRED` + `.bankOtp` / `.masterpassOtp`: yeni OTP gerekiyor.
- `ACTION_REQUIRED` + `.threeD`: OTP sonrası 3D Secure gerekiyor; `data.redirectUrl`'i açın. Ödeme OTP'si ise `data`
  içinde `paymentId`, `masterpassPaymentId`, `successUrl`, `failUrl` gibi ödeme bilgileri de döner.
- `FAILED`:
  - `OTP_IS_NOT_VALID`: kod hatalı; ödeme beklemede kalır, kullanıcı tekrar deneyebilir.
  - Masterpass'ın kesin hatasında ödeme OTP'si Paywall'a başarısız olarak bildirilir.

### `PaywallSdk.providers.masterpass.resendOtp()`

Bekleyen OTP'yi yeniden gönderir. Parametre almaz. **Olası sonuçlar:** `SUCCESS` · `ACTION_REQUIRED` (yeni OTP
gönderildi) · `FAILED` (ör. `TOKEN_ALREADY_USED`).

### `PaywallSdk.providers.masterpass.addCard(_:)`

Kullanıcının Masterpass hesabına kart ekler.

| Parametre (`AddCardParams`) | Tip | Açıklama |
|---|---|---|
| `userId` | `String` | Merchant kullanıcı ID'si |
| `accountKey` | `String` | Telefon numarası |
| `accountAliasName` | `String` | Kartın adı (ör. "Maaş kartım") |
| `cardHolderName` | `String` | Kart üzerindeki isim |
| `cardNumber` | `CardNumberInput` | `PaywallCardNumberField.input` |
| `expiryDate` | `String` | Son kullanma tarihi, **MMYY** (ör. `1226` = Aralık 2026) |
| `cvv` | `CvvInput` | `PaywallCvvField.input` |
| `termsConsent` | `TermsConsentInput` | `PaywallTermsCheckBox.input` (işaretli olmalı) |
| `requestReferenceNumber` | `String` | Benzersiz referans numarası |
| `accountKeyType` | `AccountKeyType` | `.msisdn` (varsayılan) |

**Olası sonuçlar:** `SUCCESS` (`cardAlias`) · `ACTION_REQUIRED` + OTP (`verifyOtp`) veya `.threeD` (`redirectUrl`) ·
`FAILED` (ör. `4004` kart zaten kayıtlı, `TERMS_NOT_ACCEPTED`).

### `PaywallSdk.providers.masterpass.deleteCard(_:)`

Kayıtlı kartı siler. Son kart silinse bile hesap merchant'tan ayrılmaz.

| Parametre (`DeleteCardParams`) | Tip | Açıklama |
|---|---|---|
| `accountKey` | `String` | Telefon numarası |
| `cardAlias` | `String` | Silinecek kartın alias'ı |

### `PaywallSdk.payment.initPayment(_:)`

Ödemeyi başlatır (yeni kart veya kayıtlı kart).

| Parametre (`PaymentInitParams`) | Tip | Açıklama |
|---|---|---|
| `paymentSource` | `PaymentSource` | `.registeredCard` / `.manualCard` |
| `paymentDetail` | `PaymentDetail` | Ödeme detayları (aşağıda) |
| `cardData` | `PaymentCardData` | Masterpass'a giden kart bilgisi: kayıtlı kartta `cardAlias`; yeni kartta `cardNumber`, `cardHolderName`, `expiryDate` (MMYY), `cvv` |
| `products` | `[Product]` | `productId`, `productName`, `productAmount`, opsiyonel `productCategory`, `productDescription` |
| `sessionId` | `String?` | Opsiyonel; SDK'nın kendi session'ı önceliklidir |
| `force3D` | `Bool?` | `nil` ise session ayarı kullanılır |
| `saveCard` | `Bool` | Yalnızca alias kontrolünü açar; kartı kaydetmek için `registerAndPurchase` kullanın |
| `card` | `PaymentInitCard` | Paywall'a giden maskeli kart bilgisi: `cardBin`, `cardMasked`, `ownerName`, `cardAlias` |
| `customer` | `Customer?` | `fullName`, `phone`, `customerId`, `email`, `identityNumber` |

`PaymentDetail`:

| Alan | Tip | Açıklama |
|---|---|---|
| `amount` | `Decimal` | Ödeme tutarı (ör. `100.00`) |
| `currencyId` | `Int` | Para birimi (949 TRY, 840 USD, 978 EUR) |
| `merchantUniqueCode` | `String` | Benzersiz sipariş kodu |
| `trackingCode` | `String` | Takip kodu |
| `successUrl` / `failUrl` | `String` | Başarı / hata dönüş adresleri |
| `clientIp` | `String` | Müşterinin IP adresi |
| `installment` | `Int` | Taksit sayısı (tek çekim: 1) |
| `channelId`, `tagId` | `Int?` | Opsiyonel (varsayılan 0) |

**Dönüş:** `MasterpassPaymentInitResult` — `sessionId`, `status`, `actionType`, `token` (OTP),
`retrievalReferenceNumber`, `redirectUrl` (3D), `successUrl`, `failUrl`, `paymentId`, `masterpassPaymentId`,
`activityId`, `uniqueCode`, `merchantUniqueCode`, `maskedCard` (`bin`, `last4`, `masked`).

**Olası sonuçlar:**
- `SUCCESS`: ödeme tamamlandı; `nextActionHint = "Please commit the payment."`
- `ACTION_REQUIRED` + `.bankOtp` / `.masterpassOtp`: `verifyOtp` ile devam edin.
- `ACTION_REQUIRED` + `.threeD`: `data.redirectUrl`'i açın.
- `FAILED`: `errorCode` + `message`.

### `PaywallSdk.payment.initWithRegisteredCard(_:)`

Kayıtlı kartla ödemenin kısa yolu. Parametreler (`RegisteredCardPaymentParams`): `alias`, `maskedCard`, `cardBin`,
`cardHolderName`, `paymentDetail`, `products`, opsiyonel `sessionId`, `force3D`, `customer`. Sonuç `initPayment` ile aynı.

### `PaywallSdk.payment.registerAndPurchase(_:)`

Kartı kaydedip ödeme alır.

| Parametre (`RegisterAndPurchaseParams`) | Tip | Açıklama |
|---|---|---|
| `accountKey` | `String` | Telefon numarası |
| `merchantUserId` | `String` | Merchant kullanıcı ID'si |
| `paymentDetail` | `PaymentDetail` | Ödeme detayları |
| `cardData` | `RegisterCardData` | `cardNumber`, `cardHolderName`, `expiryDate` (MMYY), `cvv`, `cardAlias` (**ZORUNLU**) |
| `termsConsent` | `TermsConsentInput` | Masterpass koşul onayı (**ZORUNLU**) |
| `products` | `[Product]` | Ürün listesi |
| `sessionId`, `customer`, `force3D` | opsiyonel | `initPayment` ile aynı |
| `accountKeyType` | `AccountKeyType` | `.msisdn` (varsayılan) |
| `isMsisdnValidatedByMerchant` | `Bool` | Varsayılan `true` |

Sonuç `initPayment` ile aynı yapıdadır.

## Response Formatları

Tüm fonksiyonlar `SdkResponse<T>` döner:

| Alan | Açıklama |
|---|---|
| `status` | `.success` / `.actionRequired` / `.failed` — **akışı buna göre dallandırın** |
| `success` | `FAILED` dışında `true` (`ACTION_REQUIRED`'da da `true`) |
| `source` | `.sdk` (SDK isteği göndermeden durdurdu) / `.paywall` / `.masterpass` |
| `message` | Açıklama |
| `errorCode` | Yalnızca `FAILED`'da (sabitler: `SdkErrorCodes`) |
| `actionType` | Yalnızca `ACTION_REQUIRED`'da: `.bankOtp`, `.masterpassOtp`, `.threeD`, `.merchantLinkRequired` |
| `data` | İşleme özel sonuç |
| `field` | Hatalı parametrenin adı (ör. `"otp"`, `"cardAlias"`) |
| `actionHint` / `nextActionHint` | Sonraki adıma dair ipucu |
| `providerMeta` | `httpStatus`, `responseCode` (ör. Masterpass `"0000"`, `"5010"`) |

### Başarılı Response

```
status: .success, success: true, source: .masterpass | .paywall | .sdk, data: …
```

### Action Required Response

```
status: .actionRequired, success: true, source: .masterpass,
actionType: .bankOtp | .masterpassOtp | .threeD | .merchantLinkRequired,
data: { token (OTP), redirectUrl (3D), … }
```

### Hata Response

```
status: .failed, success: false, source: .sdk | .paywall | .masterpass,
errorCode: "MISSING_CARD_ALIAS", message: "…", field: "cardAlias"
```

## Environment'lar

| `environment` | Paywall API | Masterpass |
|---|---|---|
| `.dev` | `https://dev-payment-api.itspaywall.com` | `https://mp-test-sdk.masterpassturkiye.com` |
| `.test` | `https://test-payment-api.itspaywall.com` | `https://mp-test-sdk.masterpassturkiye.com` |
| `.prod` | `https://payment-api.paywall.com.tr` | `https://mp-sdk.masterpassturkiye.com` |

Session bilgisi Masterpass ortamını belirtiyorsa (prod/UAT/test) o kullanılır.

## Önemli Notlar

- **Session oluşturma merchant backend tarafından yapılır**; SDK token üretmez veya yenilemez.
- `initPaywallSdk` ve `providers.masterpass.initialize()` akışın başında **bir kez** çağrılır; sonraki işlemler
  (kart listesi, ödeme, OTP…) için tekrar çağrılmaz. Yalnızca şu durumlarda yeniden çağrılmalıdır: uygulama
  kapanıp açıldıysa, işlem `SESSION_EXPIRED` döndüyse (backend'den yeni token alınır) ya da `initPaywallSdk` yeni
  bir token'la tekrar çağrıldıysa (SDK sıfırlanır, `initialize()` da tekrar gerekir).
- **SDK state'i yalnızca bellekte tutulur.** Uygulama kapanırsa session, OTP bilgisi ve bekleyen ödeme kaybolur;
  `initPaywallSdk` ve `initialize()` tekrar çağrılmalıdır.
- SDK işlemleri sırayla çalışır; aynı anda iki çağrı yapılırsa ikincisi birincinin bitmesini bekler.
- `getCardList` arka planda `accountAccess`'i çağırır; `accountAccess` adında ayrı bir fonksiyon yoktur.
- `userId`, `getCardList` için zorunludur.
- Yeni kullanıcılar için önce `linkMerchant` yapılmalıdır.
- `expiryDate` formatı **MMYY**'dir (ör. `1226` = Aralık 2026).
- `registerAndPurchase` için `cardAlias` ve koşul onayı zorunludur.
- Ödeme OTP'si beklerken `addCard` veya `linkMerchant` yeni bir OTP başlatırsa bekleyen ödeme OTP'si iptal edilir.
- OTP ve 3D ekranlarını SDK açmaz; ekranlar merchant uygulamasına aittir.
- Jailbreak'li cihazlarda Masterpass çalışmaz; `providers.masterpass.initialize()` `MASTERPASS_PROVIDER_INIT_ERROR` döner.
- `getCardList` 401 döndüğünde: yetki/token hatası (`AUTHENTICATION_FAILED`, `TOKEN_HAS_EXPIRED`, `..._IN_TOKEN` …)
  `FAILED` olarak döner (yeni token alın); diğer 401'ler `ACTION_REQUIRED` + `.masterpassOtp`'dir.

## Güvenlik

- Kart numarası, CVV ve OTP yalnızca Paywall güvenli alanlarıyla alınır; uygulama ve Paywall kodu bu değerleri
  okuyamaz. Masterpass şifreleyerek gönderir.
- Paywall'a yalnızca kartın ilk 8 hanesi (BIN) ve maskeli bilgi gider.
- CVV alanı gizli girişlidir (ekran kaydı ve ekran görüntüsünde görünmez). Güvenli alanlarda kopyalama, yapıştırma ve
  sürükleme kapalıdır.
- Ödeme ekranlarında ekran kaydını izleyin (`UIScreen.capturedDidChangeNotification`) ve uygulama arka plana
  geçerken kart formunu gizleyin.
- Token'lar yalnızca bellekte tutulur, diske yazılmaz ve loglanmaz.
- `PaywallSdk.setNetworkListener` (ağ trafiği izleme) yalnızca debug build'de çalışır.
