#  MasterPass

## Önsöz
Masterpass'ın iOS SDK'sıdır. Söz konusu SDK'nın ayrıntılı kullanımı bu dökümanda açıklanmıştır.


### Initialization of MasterPass SDK.
MasterPass SDK bileşenleri ve hizmetleri kullanılmadan önce, MasterPass SDK ilkkez başlatılmalıdır.

### Account Services
- Add Card `MasterPass.addCard(...)` :Son kullanıcının kart bilgisini sisteme eklemek için kullanılan servistir. 
- AccountAccess `MasterPass.accountAccess(...)` :Son kullanıcıya ait tüm kartları listeleyen servistir.
- Remove Card `MasterPass.removeCard(...)` : Son kullanıcıya ait belirli bir kartı silmek için kullanılan servistir.
- Complete Registration `MasterPass.completeRegistration(...)` : Son kullanıcıya ait ödeme işlemi tamamlandıktan sonra kart bilgisinin kaydedilmesi akışında kullanılan servistir.
- Link Account To Merchant `MasterPass.linkAccountToMerchant(...)` : Son kullanıcıya ait Masterpass eko sisteminde bulunan mevcut hesabı üye işyerine bağlamak için kullanılan servistir.
- Update User Msisdn `MasterPass.updateUserMsisdn(...)` :Son kullanıcıya ait cep telefonu numarasını güncellemek için kullanılan servistir.
- Add User Id `MasterPass.addUserId(...)` : Son kullanıcıya benzersiz tanımlayıcı eklemek için kullanılan servistir.
- Update User Id `MasterPass.updateUserId(...)` : Son kullanıcıya atanan benzersiz tanımlayıcı güncellemek için kullanılan servistir.
### Payment Services
- Payment `MasterPass.startPayment(...)` : Ödeme işlemi için kullanılan servistir.
- Recurring Order `MasterPass.recurringOrderCreate(...)` : Tekrarlı siparişlerin Masterpass ekosistemi üzerinden işletilmesi için kullanılan servistir.
- Recurring Order Delete `MasterPass.recurringOrderDelete(...)` : Tekrarlı siparişlerin iptali veyasonlandırılması için kullanılan servistir.
- Recurring Order Put `MasterPass.recurringOrderUpdate(...)` : Tekrarlı siparişler üzerinde yapılacak değişilikler için kullanılan servistir.
- Register And Purchase `MasterPass.registerAndPurchase(...)` : Son kullanıcıya ait kart bilgisinin kayıt işleminin ardından ödeme işleminin yapıldığı akış için kullanılan servistir.
- Direct Payment `MasterPass.directPayment(...)` :: Son kullanıcıya ait kayıtlı kartın olmadığı veya kayıtlı olan kartların kullanılmak istenmediği durumlarda kullanılan servistir.

### Verify Service

- Verify `MasterPass.verify(...)` :  Kullanıcıya ait tek kullanımlık şifre gerektiren işlemlerde,
  tek kullanımlık şifrenin doğrulanması için kullanılan servistir.
- Resend OTP `MasterPass.resendOtp(...)` : Tek kullanımlık şifrenin tekrar gönderilmesi için kullanılan servistir.

### Usage of Custom Components
- MPText `MPText` : "CARDNUMBER, CVV, OTP, MPIN, RTA, CVC" giriş alanlarının son kullanıcı ile etkileşime girdiği ön yüz tasarımlarında kullanılmak üzere tasarlanmış bir bileşendir.
- MPWebView `MPWebView` : "3D" işlemlerinde kullanılmak üzere ön yüz tasarımlarda ilgili yönlendirmeleri yapmak üzere tasarlanmış bir bileşendir.
- MpCheckBox `MPCheckbox` : Şartlar ve Koşullar" benzeri kullanıcıdan onaylandığına dair etkileşim alınması için tasarılanmış bir bileşendir.

- MpCheckBox SwiftUI kullanım örneği:

- @State var checkbox: MPCheckBox?
- @State private var isTermsAccepted: Bool = true

- MasterpassCheckBox(state: $isTermsAccepted, container: $checkbox) { state in
-                        Toggle("Terms and Conditions", isOn: .constant(state))
-                    }

- MpCheckBox @IBOutlet kullanım örneği:
-
- @IBOutlet weak var termsCheckboxView: MasterpassUIKitCheckBox!

    

    override func viewDidLoad() {

        super.viewDidLoad()

        

        termsCheckboxView.onStateChanged = { isAccepted in

            if isAccepted {

                print("true")

            } else {

                print("false")

            }

        }

    }
-
-
-
- MpCheckBox UIKit kullanım örneği:

- private let termsCheckboxView = MasterpassUIKitCheckBox()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {

        termsCheckboxView.titleText = "Aydınlatma Metni'ni okudum ve onaylıyorum"
        termsCheckboxView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(termsCheckboxView)
        
        NSLayoutConstraint.activate([
            termsCheckboxView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            termsCheckboxView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            termsCheckboxView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        

        termsCheckboxView.onStateChanged = { isAccepted in
            print("Sözleşme durumu değişti: \(isAccepted)")
        }
    }
