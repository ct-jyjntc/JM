import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("网络") {
                Button {
                    Task { await viewModel.discoverEndpoints(settings: settings) }
                } label: {
                    Label(viewModel.isDiscoveringEndpoints ? "检测中" : "刷新官方线路状态", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(viewModel.isDiscoveringEndpoints)

                if !viewModel.endpointProbes.isEmpty {
                    ForEach(viewModel.endpointProbes) { probe in
                        EndpointProbeRow(probe: probe)
                    }
                }

                Picker("本地代理", selection: $settings.proxyMode) {
                    ForEach(ProxyMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.proxyMode) { _, _ in viewModel.configureProxy(settings: settings) }

                if settings.proxyMode != .off {
                    TextField("代理主机", text: $settings.proxyHost)
                        .onChange(of: settings.proxyHost) { _, _ in viewModel.configureProxy(settings: settings) }
                    TextField("代理端口", value: $settings.proxyPort, format: .number)
                        .onChange(of: settings.proxyPort) { _, _ in viewModel.configureProxy(settings: settings) }
                }
            }

            Section("阅读") {
                Picker("图片线路", selection: $settings.imageShunt) {
                    ForEach(AppSettings.imageShunts, id: \.self) { shunt in
                        Text("线路 \(shunt)").tag(shunt)
                    }
                }

                Picker("预取页数", selection: $settings.prefetchCount) {
                    ForEach(AppSettings.prefetchCounts, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }

                Picker("缓存上限", selection: $settings.readerCacheLimitMB) {
                    ForEach(AppSettings.cacheLimitOptionsMB, id: \.self) { limit in
                        Text("\(limit) MB").tag(limit)
                    }
                }

                HStack {
                    if let stats = viewModel.cacheStats {
                        Text("\(Formatters.byteString(stats.totalBytes)) / \(Formatters.byteString(stats.cacheLimitBytes))，\(stats.fileCount) 个文件")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("尚未读取缓存状态")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("刷新", systemImage: "arrow.clockwise") {
                        Task { await viewModel.loadCacheStats(settings: settings) }
                    }
                    Button("打开", systemImage: "folder") {
                        viewModel.openCacheDirectory()
                    }
                    Button("清理", systemImage: "trash", role: .destructive) {
                        Task { await viewModel.clearCache(settings: settings) }
                    }
                }
            }

            Section("显示") {
                Picker("主题", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("隐藏封面", isOn: $settings.hideCovers)
                Button("恢复默认", systemImage: "arrow.counterclockwise") {
                    settings.reset()
                    viewModel.configureProxy(settings: settings)
                }
            }

            if let error = viewModel.errorMessage {
                Section("错误") {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical)
        .navigationTitle("设置")
        .task {
            viewModel.configureProxy(settings: settings)
            await viewModel.loadCacheStats(settings: settings)
        }
    }
}

private struct EndpointProbeRow: View {
    let probe: ApiEndpointProbe

    var body: some View {
        HStack {
            Label(probe.endpoint, systemImage: probe.available ? "checkmark.circle" : "xmark.circle")
                .foregroundStyle(probe.available ? .primary : .secondary)
            Spacer()
            if let latency = probe.latencyMS {
                Text("\(latency) ms")
                    .foregroundStyle(.secondary)
            }
        }
        .help(probe.error ?? probe.imageHost ?? probe.endpoint)
    }
}
