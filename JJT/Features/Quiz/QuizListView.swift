import SwiftUI

// MARK: - 共享顶栏（对齐安卓 QuizTopBar）

struct QuizTopBar: View {
    let title: String
    let subtitle: String
    var onBack: (() -> Void)? = nil
    var actionIcon: String? = nil
    var onAction: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Button {
                if let onBack { onBack() } else { dismiss() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Noir.goldLight)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
            }
            Spacer()
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .tracking(4)
                    .foregroundStyle(Noir.goldText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 8.5, design: .serif))
                    .italic()
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer()
            if let actionIcon, let onAction {
                Button(action: onAction) {
                    Image(systemName: actionIcon)
                        .font(.system(size: 14))
                        .foregroundStyle(Noir.goldLight)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

// MARK: - 测评列表（对齐安卓 QuizListScreen）

struct QuizListView: View {

    var onBack: (() -> Void)? = nil

    @StateObject private var vm = QuizListViewModel()
    @State private var introQuizId: Int64?
    @State private var resultQuizId: Int64?

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                QuizTopBar(title: "属性测试", subtitle: "PERSONA TRIALS", onBack: onBack)
                Rectangle().fill(Noir.goldLine).frame(height: 1)
                if vm.isLoading {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else if vm.quizzes.isEmpty {
                    Spacer()
                    Text("暂无测试")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(vm.quizzes) { quiz in
                                quizRow(quiz)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .onAppear { vm.load() }
        .fullScreenCover(item: Binding(
            get: { introQuizId.map { QuizTarget(id: $0) } },
            set: { introQuizId = $0?.id }
        )) { target in
            QuizIntroView(quizId: target.id)
        }
        .fullScreenCover(item: Binding(
            get: { resultQuizId.map { QuizTarget(id: $0) } },
            set: { resultQuizId = $0?.id }
        )) { target in
            QuizResultView(quizId: target.id)
        }
    }

    private struct QuizTarget: Identifiable { let id: Int64 }

    private func quizRow(_ quiz: QuizInfo) -> some View {
        let completed = vm.completedQuizIds.contains(quiz.id)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(red: 0x3D/255, green: 0x2B/255, blue: 0x0E/255), Color(red: 0x1A/255, green: 0x0E/255, blue: 0x14/255)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 52, height: 52)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Noir.gold.opacity(0.25), lineWidth: 1))
                if let icon = quiz.iconUrl, !icon.isEmpty {
                    WebImage(url: webImageURL(icon), contentMode: .fill) {
                        Image(systemName: "testtube.2")
                            .foregroundStyle(Noir.goldLight.opacity(0.7))
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    Image(systemName: "testtube.2")
                        .font(.system(size: 20))
                        .foregroundStyle(Noir.goldLight.opacity(0.7))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(quiz.name ?? "")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Noir.ivory)
                if let sub = quiz.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
                Text("\(quiz.totalQuestions ?? 0) 题 · \(quiz.partCount ?? 1) 部分")
                    .font(.system(size: 10))
                    .foregroundStyle(Noir.goldLight.opacity(0.6))
            }
            Spacer()
            Text(completed ? "看结果" : "开始")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(completed ? .white.opacity(0.4) : Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(completed
                            ? AnyShapeStyle(Color.white.opacity(0.06))
                            : AnyShapeStyle(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .leading, endPoint: .trailing)))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.hairlineGold, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            if completed { resultQuizId = quiz.id } else { introQuizId = quiz.id }
        }
    }
}

@MainActor
final class QuizListViewModel: ObservableObject {
    @Published var quizzes: [QuizInfo] = []
    @Published var completedQuizIds: Set<Int64> = []
    @Published var isLoading = false

    func load() {
        isLoading = true
        Task {
            async let list = QuizAPI.list()
            async let results = QuizAPI.myResults()
            quizzes = (try? await list) ?? []
            completedQuizIds = Set(((try? await results) ?? []).compactMap(\.quizId))
            isLoading = false
        }
    }
}

// MARK: - 测评介绍（对齐安卓 QuizIntroScreen）

struct QuizIntroView: View {

    let quizId: Int64
    var onBack: (() -> Void)? = nil

    @State private var detail: QuizDetail?
    @State private var isLoading = true
    @State private var showAnswer = false

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                QuizTopBar(title: detail?.name ?? "属性测试", subtitle: "TRIAL DETAILS", onBack: onBack)
                Rectangle().fill(Noir.goldLine).frame(height: 1)
                if isLoading {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else if let detail {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // 头部：图标 + 名称
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(LinearGradient(colors: [Color(red: 0x3D/255, green: 0x2B/255, blue: 0x0E/255), Color(red: 0x1A/255, green: 0x0E/255, blue: 0x14/255)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 64, height: 64)
                                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.gold.opacity(0.25), lineWidth: 1))
                                    if let icon = detail.iconUrl, !icon.isEmpty {
                                        WebImage(url: webImageURL(icon), contentMode: .fill) {
                                            Image(systemName: "testtube.2").foregroundStyle(Noir.goldLight.opacity(0.7))
                                        }
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                    } else {
                                        Image(systemName: "testtube.2")
                                            .font(.system(size: 24))
                                            .foregroundStyle(Noir.goldLight.opacity(0.7))
                                    }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(detail.name ?? "")
                                        .font(.system(size: 19, weight: .bold, design: .serif))
                                        .foregroundStyle(Noir.ivory)
                                    if let sub = detail.subtitle, !sub.isEmpty {
                                        Text(sub)
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(Noir.goldLight.opacity(0.7))
                                    }
                                }
                            }

                            divider

                            sectionHeader("规则说明", "RULES")
                            Text(detail.description ?? "暂无说明")
                                .font(.system(size: 13.5))
                                .lineSpacing(8.5)
                                .foregroundStyle(.white.opacity(0.7))

                            if let dims = detail.dimensions, !dims.isEmpty {
                                divider
                                sectionHeader("测试维度", "DIMENSIONS")
                                FlowRow(spacing: 8) {
                                    ForEach(dims.compactMap(\.label), id: \.self) { label in
                                        Text(label)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.75))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 5)
                                            .background(Noir.noir2)
                                            .clipShape(Capsule())
                                            .overlay(Capsule().stroke(Noir.hairlineGold, lineWidth: 1))
                                    }
                                }
                            }

                            divider
                            Text("共 \(detail.totalQuestions ?? 0) 题 · \(detail.partCount ?? 1) 部分 · 约 3 分钟")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    // 开始按钮
                    Button { showAnswer = true } label: {
                        Text("开始测试")
                            .font(.system(size: 14, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
        .onAppear { load() }
        .fullScreenCover(isPresented: $showAnswer) {
            QuizAnswerView(quizId: quizId)
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
        .padding(.bottom, 8)
    }

    private func load() {
        Task {
            detail = try? await QuizAPI.detail(quizId: quizId)
            isLoading = false
        }
    }
}

/// 简易流式布局（维度标签换行）
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
