import PaywallSDK
import SwiftUI
import WebKit

/// OTP entry with the SDK secure OTP field.
struct OtpSheet: View {
    @ObservedObject var state: HarnessState
    @ObservedObject var otp: PaywallSecureTextState
    let request: OtpRequest

    init(state: HarnessState, request: OtpRequest) {
        self.state = state
        otp = state.otp
        self.request = request
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(request.message).font(.subheadline).foregroundStyle(.secondary)
                SecureFieldFrame(label: "Doğrulama kodu", info: "\(otp.digitCount) hane") {
                    PaywallSecureTextFieldView(state: otp, placeholder: "6 haneli kod", configure: plainSecureField)
                }
                if let message = state.otpResendMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(message.contains("gönderilemedi") || message.contains("hata") ? .red : .secondary)
                }
                Button { state.submitOtp() } label: {
                    VStack(spacing: 2) {
                        Text("providers.masterpass.verifyOtp(...)").font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        Text("Kodu doğrular").font(.caption).opacity(0.85)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .disabled(otp.digitCount == 0)
                Button { state.resendOtp() } label: {
                    HStack(spacing: 6) {
                        if state.otpResendLoading { ProgressView().controlSize(.small) }
                        Text("providers.masterpass.resendOtp()").font(.system(.footnote, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(state.otpResendLoading)
                Spacer()
            }
            .padding()
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { state.cancelOtp() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// 3D Secure page in a plain `WKWebView`. Masterpass' `MPWebView` is not used: it rewrites the URL with its own
/// `mobileReturnUrl`, while Paywall already appended its return URL.
struct ThreeDSheet: View {
    let request: ThreeDRequest
    let onFinished: (String, String) -> Void
    @State private var currentUrl = ""

    var body: some View {
        NavigationStack {
            ThreeDWebView(request: request, currentUrl: $currentUrl, onFinished: onFinished)
                .navigationTitle(currentUrl)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Kapat") { onFinished("3D: kullanıcı kapattı", currentUrl) }
                    }
                }
        }
    }
}

private struct ThreeDWebView: UIViewRepresentable {
    let request: ThreeDRequest
    @Binding var currentUrl: String
    let onFinished: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: request.url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: ThreeDWebView
        private var finished = false

        init(_ parent: ThreeDWebView) { self.parent = parent }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url?.absoluteString ?? ""
            parent.currentUrl = url
            if !finished, let success = parent.request.successUrl, !success.isEmpty, url.hasPrefix(success) {
                finished = true
                parent.onFinished("3D: successUrl'e dönüldü", url)
                decisionHandler(.cancel)
                return
            }
            if !finished, let fail = parent.request.failUrl, !fail.isEmpty, url.hasPrefix(fail) {
                finished = true
                parent.onFinished("3D: failUrl'e dönüldü", url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
