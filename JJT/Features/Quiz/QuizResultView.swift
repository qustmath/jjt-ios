import SwiftUI

/// 测试结果页（对齐安卓 QuizResultScreen）
/// 数据源：my-results 找 resultKey → result-detail + dimScoresJson；底部：重测 / 回顾
struct QuizResultView: View {

    let quizId: Int64
    var onBack: (() -> Void)? = nil

    @StateObject private var vm = QuizResultViewModel()
    @State private var retakeId: Int64?
    @State private var reviewId: Int64?

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                QuizTopBar(title: "测试结果", subtitle: "TRIAL VERDICT", onBack: onBack)
                Rectangle().fill(Noir.goldLine).frame(height: 1)
                if vm.isLoading {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else if vm.hasResult {
                    resultBody
                    bottomBar
                } else {
                    Spacer()
                    Text("暂无测试结果")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                }
            }
        }
        .onAppear { vm.load(quizId: quizId) }
        .fullScreenCover(item: Binding(
            get: { retakeId.map { T(id: $0) } },
            set: { retakeId = $0?.id }
        )) { t in
            QuizAnswerView(quizId: t.id)
        }
        .fullScreenCover(item: Binding(
            get: { reviewId.map { T(id: $0) } },
            set: { reviewId = $0?.id }
        )) { t in
            QuizAnswerView(quizId: t.id, reviewMode: true)
        }
    }

    private struct T: Identifiable { let id: Int64 }

    // MARK: - 内容

    private var resultBody: some View {
        let detail = vm.resultDetail
        let title = detail?.title ?? vm.resultInfo?.resultTitle ?? ""
        let subtitle = detail?.subtitle ?? vm.resultInfo?.resultTitle
        let iconUrl = detail?.iconUrl ?? vm.resultInfo?.quizIconUrl
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 结果标题卡（金框取景角）
                VStack(spacing: 14) {
                    if let icon = iconUrl, !icon.isEmpty {
                        WebImage(url: webImageURL(icon), contentMode: .fill) {
                            Image(systemName: "sparkles").foregroundStyle(Noir.goldLight)
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.gold.opacity(0.25), lineWidth: 1))
                    }
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .tracking(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Noir.goldText)
                    if let subtitle, !subtitle.isEmpty, subtitle != title {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Noir.noir2)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Noir.gold.opacity(0.3), lineWidth: 1))
                .overlay(CornerFrame(color: Noir.goldLight.opacity(0.5), margin: 10, arm: 14))

                if let desc = detail?.description, !desc.isEmpty {
                    divider
                    Text(desc)
                        .font(.system(size: 13.5))
                        .lineSpacing(8.5)
                        .foregroundStyle(.white.opacity(0.7))
                }

                // 维度得分
                if !vm.dimScores.isEmpty {
                    divider
                    sectionHeader("维度得分", "DIMENSIONS")
                    let maxScore = max(vm.dimScores.values.max() ?? 1, 1)
                    ForEach(Array(vm.dimScores.keys.sorted()), id: \.self) { key in
                        dimensionRow(label: vm.dimLabels[key] ?? key,
                                     score: vm.dimScores[key] ?? 0, maxScore: maxScore)
                    }
                }

                if let comp = detail?.compatible, !comp.isEmpty {
                    divider
                    sectionHeader("适合搭档", "COMPATIBLE")
                    Text(comp)
                        .font(.system(size: 13.5))
                        .lineSpacing(8.5)
                        .foregroundStyle(.white.opacity(0.7))
                }

                if let styles = detail?.playStyles, !styles.isEmpty {
                    divider
                    sectionHeader("玩法风格", "PLAY STYLES")
                    FlowRow(spacing: 8) {
                        ForEach(styles, id: \.self) { style in
                            Text(style)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Noir.noir2)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))
                        }
                    }
                }

                if let ct = vm.resultInfo?.createTime, !ct.isEmpty {
                    divider
                    Text("测试时间: \(ct)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            .padding(.vertical, 16)
    }

    private func sectionHeader(_ title: String, _ en: String) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundStyle(Noir.ivory)
            Text(en)
                .font(.system(size: 8, design: .serif))
                .italic()
                .tracking(2)
                .foregroundStyle(.white.opacity(0.25))
                .padding(.bottom, 2)
        }
        .padding(.bottom, 10)
    }

    private func dimensionRow(label: String, score: Int, maxScore: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Noir.ivory)
                Spacer()
                Text("\(score)")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(Noir.goldText)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(LinearGradient(colors: [Noir.goldDeep, Noir.gold, Noir.goldPale],
                                                  startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(score) / CGFloat(maxScore))
                }
            }
            .frame(height: 4)
        }
        .padding(.bottom, 10)
    }

    // MARK: - 底部按钮

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Noir.goldLine).frame(height: 1)
            HStack(spacing: 12) {
                Button { reviewId = quizId } label: {
                    Text("答题回顾")
                        .font(.system(size: 13))
                        .foregroundStyle(Noir.goldLight)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(Capsule().stroke(Noir.gold.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button { retakeId = quizId } label: {
                    Text("再测一次")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - ViewModel（对齐安卓 QuizResultViewModel）

@MainActor
final class QuizResultViewModel: ObservableObject {

    @Published var isLoading = true
    @Published var resultInfo: MyResultInfo?
    @Published var resultDetail: ResultDetailInfo?
    @Published var dimScores: [String: Int] = [:]
    @Published var dimLabels: [String: String] = [:]

    var hasResult: Bool { resultInfo != nil || resultDetail != nil }

    func load(quizId: Int64) {
        Task {
            // my-results 里找该测试的最新结果
            let results = (try? await QuizAPI.myResults()) ?? []
            let matched = results.last { $0.quizId == quizId } ?? results.first { $0.quizId == quizId }
            resultInfo = matched
            if let key = matched?.resultKey {
                resultDetail = try? await QuizAPI.resultDetail(quizId: quizId, resultKey: key)
            }
            // 维度得分（dimScoresJson 是 JSON 字符串）
            if let json = matched?.dimScoresJson, let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
                dimScores = obj
            }
            // 维度 label 映射
            if let d = try? await QuizAPI.detail(quizId: quizId), let dims = d.dimensions {
                for dim in dims {
                    if let k = dim.key, let l = dim.label { dimLabels[k] = l }
                }
            }
            isLoading = false
        }
    }
}
