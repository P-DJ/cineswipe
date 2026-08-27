import SwiftData
import SwiftUI

struct FilterView: View {
    @ObservedObject var viewModel: CineSwipeViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var draft: DiscoverFilter
    @State private var isShowingAbout = false

    private let regions = [
        ("US", "美国"),
        ("JP", "日本"),
        ("KR", "韩国"),
        ("CN", "中国大陆"),
        ("TW", "中国台湾"),
        ("GB", "英国"),
        ("FR", "法国")
    ]

    init(viewModel: CineSwipeViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: viewModel.appliedFilter)
    }

    var body: some View {
        NavigationStack {
            Form {
                mediaTypeSection

                if let type = draft.mediaType {
                    genreSection(for: type)
                    regionSection
                    yearSection
                    ratingSection
                }

                Section {
                    Button("关于 CineSwipe") {
                        isShowingAbout = true
                    }
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("应用") {
                        let filter = draft
                        dismiss()
                        Task {
                            await viewModel.apply(filter, in: modelContext)
                        }
                    }
                    .disabled(!draft.isValid)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("重置为混合模式", role: .destructive) {
                    dismiss()
                    Task {
                        await viewModel.resetFilter(in: modelContext)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.bar)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingAbout) {
            AboutView()
        }
    }

    private var mediaTypeSection: some View {
        Section("内容类型") {
            Picker("内容类型", selection: mediaTypeBinding) {
                Text("电影").tag(MediaType.movie as MediaType?)
                Text("电视剧").tag(MediaType.tv as MediaType?)
            }
            .pickerStyle(.segmented)

            if draft.mediaType == nil {
                Text("选择一种内容类型后才能应用自定义筛选。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func genreSection(for type: MediaType) -> some View {
        Section("类型") {
            if let genres = viewModel.genres[type], !genres.isEmpty {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 8),
                        count: 3
                    ),
                    spacing: 8
                ) {
                    ForEach(genres) { genre in
                        selectionButton(
                            genre.name,
                            isSelected: draft.genreIDs.contains(genre.id)
                        ) {
                            toggleGenre(genre.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("类型列表暂不可用")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var regionSection: some View {
        Section("地区") {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: 3
                ),
                spacing: 8
            ) {
                ForEach(regions, id: \.0) { code, name in
                    selectionButton(
                        name,
                        isSelected: draft.regions.contains(code)
                    ) {
                        toggleRegion(code)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var yearSection: some View {
        Section("年份") {
            HStack {
                yearPicker("起始", selection: $draft.startYear)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                yearPicker("结束", selection: $draft.endYear)
            }

            if let start = draft.startYear,
               let end = draft.endYear,
               start > end {
                Text("起始年份不能晚于结束年份。")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var ratingSection: some View {
        Section("最低评分") {
            Toggle("设置最低评分", isOn: ratingEnabled)

            if draft.minimumRating != nil {
                HStack {
                    Slider(
                        value: ratingValue,
                        in: 0...10,
                        step: 0.5
                    )
                    Text(String(format: "%.1f+", draft.minimumRating ?? 0))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 64, alignment: .trailing)
                }
            }

            Text("所有请求始终要求至少 100 个 TMDB 投票。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var mediaTypeBinding: Binding<MediaType?> {
        Binding(
            get: { draft.mediaType },
            set: { draft.selectMediaType($0) }
        )
    }

    private var ratingEnabled: Binding<Bool> {
        Binding(
            get: { draft.minimumRating != nil },
            set: { draft.minimumRating = $0 ? 7 : nil }
        )
    }

    private var ratingValue: Binding<Double> {
        Binding(
            get: { draft.minimumRating ?? 0 },
            set: { draft.minimumRating = $0 }
        )
    }

    private func yearPicker(
        _ title: String,
        selection: Binding<Int?>
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .fixedSize()

            Picker("", selection: selection) {
                Text("不限").tag(Int?.none)
                ForEach(years, id: \.self) { year in
                    Text(String(year)).tag(Optional(year))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: .now)
        return Array((1900...current).reversed())
    }

    private func selectionButton(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundStyle(isSelected ? .black : .white)
                .background(
                    isSelected ? Color.white : Color.white.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggleGenre(_ id: Int) {
        if let index = draft.genreIDs.firstIndex(of: id) {
            draft.genreIDs.remove(at: index)
        } else {
            draft.genreIDs.append(id)
        }
    }

    private func toggleRegion(_ code: String) {
        if let index = draft.regions.firstIndex(of: code) {
            draft.regions.remove(at: index)
        } else {
            draft.regions.append(code)
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "film.stack.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(.white)

                    VStack(spacing: 6) {
                        Text("CineSwipe")
                            .font(.title.bold())
                        Text("版本 1.0")
                            .foregroundStyle(.secondary)
                    }

                    Text("TMDB")
                        .font(.title3.bold())
                        .foregroundStyle(.cyan)
                        .accessibilityLabel("The Movie Database")

                    VStack(alignment: .leading, spacing: 14) {
                        Text("数据来源")
                            .font(.headline)
                        Text("影视资料和图片由 TMDB 提供。")
                        Text(
                            "This product uses the TMDB API but is not "
                                + "endorsed or certified by TMDB."
                        )
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Divider()

                        Text("隐私")
                            .font(.headline)
                        Text(
                            "无需登录。想看、已看和临时跳过数据只保存在本机，"
                                + "不会上传，也不用于行为分析或广告追踪。"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
            }
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
