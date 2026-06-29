import Observation
import SwiftUI
import WebKit

struct PurchaseWebView: View {
    let comicTitle: String
    let url: URL
    let relatedCookieURLs: [URL]
    let refreshStatus: () async -> String
    let persistCookies: () async -> Void
    let openExternal: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var navigation = PurchaseWebNavigation()
    @State private var statusMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("购买")
                        .font(.headline)
                    Text(comicTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("后退", systemImage: "chevron.left") {
                    navigation.goBack()
                }
                .labelStyle(.iconOnly)
                .disabled(!navigation.canGoBack)
                .help("后退")

                Button("前进", systemImage: "chevron.right") {
                    navigation.goForward()
                }
                .labelStyle(.iconOnly)
                .disabled(!navigation.canGoForward)
                .help("前进")

                Button("刷新网页", systemImage: "arrow.clockwise") {
                    navigation.reload()
                }
                .labelStyle(.iconOnly)
                .help("刷新网页")

                Button("刷新购买状态", systemImage: "checkmark.seal") {
                    Task {
                        await navigation.syncCookies()
                        await persistCookies()
                        statusMessage = await refreshStatus()
                    }
                }
                Button("浏览器打开", systemImage: "safari", action: openExternal)
                Button("关闭", systemImage: "xmark") {
                    Task {
                        await navigation.syncCookies()
                        await persistCookies()
                        dismiss()
                    }
                }
                .labelStyle(.iconOnly)
                .help("关闭")
            }
            .padding(12)

            if let statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            Divider()

            PurchaseWebContentView(url: url, relatedCookieURLs: relatedCookieURLs, navigation: navigation)
        }
        .frame(minWidth: 960, minHeight: 720)
        .onDisappear {
            Task {
                await navigation.syncCookies()
                await persistCookies()
            }
        }
    }
}

private struct PurchaseWebContentView: NSViewRepresentable {
    let url: URL
    let relatedCookieURLs: [URL]
    let navigation: PurchaseWebNavigation

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        navigation.attach(webView)
        Task { @MainActor in
            await WebCookieBridge.copySharedCookies(to: configuration.websiteDataStore.httpCookieStore, for: [url] + relatedCookieURLs)
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url, webView.url == nil else { return }
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(navigation: navigation)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let navigation: PurchaseWebNavigation

        init(navigation: PurchaseWebNavigation) {
            self.navigation = navigation
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            self.navigation.update(from: webView, isLoading: true)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            self.navigation.update(from: webView, isLoading: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.navigation.update(from: webView, isLoading: false)
            Task { @MainActor in
                await WebCookieBridge.copyWebCookiesToShared(from: webView.configuration.websiteDataStore.httpCookieStore)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            self.navigation.update(from: webView, isLoading: false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            self.navigation.update(from: webView, isLoading: false)
        }
    }
}

@MainActor
@Observable
private final class PurchaseWebNavigation {
    var canGoBack = false
    var canGoForward = false
    var isLoading = false

    private weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
        update(from: webView, isLoading: webView.isLoading)
    }

    func update(from webView: WKWebView, isLoading: Bool) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        self.isLoading = isLoading
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    func syncCookies() async {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        await WebCookieBridge.copyWebCookiesToShared(from: store)
    }
}
