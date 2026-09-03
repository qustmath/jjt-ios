import SwiftUI

/// 答题页（对齐安卓 QuizAnswerScreen）
/// 左右滑切题 + 进度条 + 上一题/下一题·提交 + 答题总览；reviewMode 只读回顾
struct QuizAnswerView: View {

    let quizId: Int64
    var reviewMode: Bool = false
    var onBack: (() -> Void)? = nil

    @StateObject private var vm = QuizAnswerViewModel()
    @State private var showOverview = false
    @State private var resultQuizId: Int64?

    private var total: Int { vm.questions.count }
    private var answeredCount: Int { vm.answers.count }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                QuizTopBar(
                    title: reviewMode ? "答题回顾" : (total > 0 ? "第\(vm.currentIndex + 1)/\(total) 题" : "答题中"),
                    subtitle: reviewMode ? "REVIEW" : (total > 0 ? "已答 \(answeredCount)/\(total)" : "ANSWERING"),
                    onBack: onBack,
                    actionIcon: "square.grid.2x2",
                    onAction: { showOverview = true }
                )
                Rectangle().fill(Noir.goldLine).frame(height: 1)
                // 鎏金进度条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.06))
                        Rectangle().fill(LinearGradient(colors: [Noir.goldDeep, Noir.gold, Noir.goldPale],
                                                        startPoint: .leading, endPoint: .trailing))
                            .frame(width: total > 0 ? geo.size.width * CGFloat(vm.currentIndex + 1) / CGFloat(total) : 0)
                    }
                }
                .frame(height: 3)

                if vm.isLoading {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else if !vm.questions.isEmpty {
                    // 左右滑切题（对齐安卓 HorizontalPager）
                    TabView(selection: $vm.currentIndex) {
                        ForEach(Array(vm.questions.enumerated()), id: \.element.id) { idx, q in
                            questionPage(q)
                                .tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    bottomBar
                } else {
                    Spacer()
                    Text("暂无题目")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                }
            }
        }
        .onAppear { vm.load(quizId: quizId, reviewMode: reviewMode) }
        .sheet(isPresented: $showOverview) {
            overviewSheet
                .presentationDetents([.medium])
                .presentationBackground(Noir.noir)
        }
        .fullScreenCover(item: Binding(
            get: { resultQuizId.map { T(id: $0) } },
            set: { resultQuizId = $0?.id }
        )) { t in
            QuizResultView(quizId: t.id)
        }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("知道了") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
        .onChange(of: vm.submitSuccess) { _, ok in
            if ok { resultQuizId = quizId }
        }
        .jjtPageGestures()
    }

    private struct T: Identifiable { let id: Int64 }

    // MARK: - 题目页

    private func questionPage(_ q: QuestionInfo) -> some View {
        let selected = vm.answers[q.id]
        let likert = (vm.quizDetail?.optionStyle ?? "scenario") == "likert"
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let part = q.partIndex {
                    Text("第\(part + 1)部分")
                        .font(.system(size: 11.5, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(Noir.goldLight)
                        .padding(.bottom, 8)
                }
                Text(q.content ?? "")
                    .font(.system(size: 17, weight: .medium))
                    .lineSpacing(9)
                    .foregroundStyle(Noir.ivory)
                    .padding(.bottom, 24)
                // 选项（回顾模式只读）
                VStack(spacing: 10) {
                    ForEach(Array((q.options ?? []).enumerated()), id: \.offset) { idx, opt in
                        optionRow(q, index: idx, option: opt, selected: selected == idx, likert: likert)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func optionRow(_ q: QuestionInfo, index: Int, option: OptionInfo, selected: Bool, likert: Bool) -> some View {
        let likertLabels = ["完全不符合", "有点不符合", "中立", "有点符合", "完全符合"]
        let label = likert ? (index < likertLabels.count ? likertLabels[index] : (option.label ?? "")) : (option.label ?? "")
        return HStack {
            Text(label)
                .font(.system(size: 14, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Noir.goldLight : .white.opacity(0.8))
                .lineSpacing(7)
            Spacer()
            if selected {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 20, height: 20)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, likert ? 12 : 14)
        .background(selected ? Noir.noir3 : Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(selected ? Noir.gold.opacity(0.55) : Noir.hairlineGold, lineWidth: selected ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture {
            if !reviewMode { vm.selectOption(questionId: q.id, optionIndex: index) }
        }
    }

    // MARK: - 底部按钮

    private var bottomBar: some View {
        let isLast = vm.currentIndex == total - 1
        let allAnswered = answeredCount == total
        return VStack(spacing: 0) {
            Rectangle().fill(Noir.goldLine).frame(height: 1)
            HStack(spacing: 12) {
                Button { withAnimation { vm.currentIndex = max(0, vm.currentIndex - 1) } } label: {
                    Text("上一题")
                        .font(.system(size: 13))
                        .foregroundStyle(vm.currentIndex > 0 ? Noir.goldLight : .white.opacity(0.25))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(Capsule().stroke(Noir.gold.opacity(vm.currentIndex > 0 ? 0.5 : 0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(vm.currentIndex == 0)

                if reviewMode {
                    Button { withAnimation { vm.currentIndex = min(total - 1, vm.currentIndex + 1) } } label: {
                        Text("下一题")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLast)
                } else if isLast {
                    Button { vm.submit(quizId: quizId) } label: {
                        Text(allAnswered ? "提交" : "提交（\(total - answeredCount) 题未答）")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                allAnswered
                                    ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                                    : AnyShapeStyle(Color.white.opacity(0.08))
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!allAnswered || vm.submitting)
                } else {
                    Button { withAnimation { vm.currentIndex = min(total - 1, vm.currentIndex + 1) } } label: {
                        Text("下一题")
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 答题总览

    private var overviewSheet: some View {
        VStack(spacing: 12) {
            Text("答题总览")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Noir.goldText)
                .padding(.top, 20)
            Text("已答 \(answeredCount)/\(total)")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                    ForEach(Array(vm.questions.enumerated()), id: \.element.id) { idx, q in
                        let answered = vm.answers[q.id] != nil
                        Button {
                            showOverview = false
                            withAnimation { vm.currentIndex = idx }
                        } label: {
                            Text("\(idx + 1)")
                                .font(.system(size: 13, weight: answered ? .bold : .regular))
                                .foregroundStyle(answered ? Color(red: 0x2A/255, green: 0x1C/255, blue: 0x06/255) : .white.opacity(0.5))
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(answered
                                            ? AnyShapeStyle(LinearGradient(colors: [Noir.goldPale, Noir.gold], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            : AnyShapeStyle(Noir.noir2))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(idx == vm.currentIndex ? Noir.crimsonHot : Noir.hairlineGold, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - ViewModel（对齐安卓 QuizAnswerViewModel）

@MainActor
final class QuizAnswerViewModel: ObservableObject {

    @Published var questions: [QuestionInfo] = []
    @Published var quizDetail: QuizDetail?
    @Published var answers: [Int64: Int] = [:]
    @Published var currentIndex = 0
    @Published var isLoading = false
    @Published var submitting = false
    @Published var submitSuccess = false
    @Published var error: String?

    func load(quizId: Int64, reviewMode: Bool) {
        isLoading = true
        Task {
            async let qs = QuizAPI.questions(quizId: quizId)
            async let d = QuizAPI.detail(quizId: quizId)
            questions = (try? await qs) ?? []
            quizDetail = try? await d
            // 回顾模式：回填我的答案
            if reviewMode, let mine = try? await QuizAPI.myAnswers(quizId: quizId) {
                for a in mine { answers[a.questionId] = a.optionIndex }
            }
            isLoading = false
        }
    }

    func selectOption(questionId: Int64, optionIndex: Int) {
        answers[questionId] = optionIndex
    }

    func submit(quizId: Int64) {
        guard !submitting else { return }
        let items = questions.compactMap { q -> AnswerItem? in
            guard let opt = answers[q.id] else { return nil }
            return AnswerItem(questionId: q.id, optionIndex: opt)
        }
        guard items.count == questions.count else {
            error = "还有题目未作答"
            return
        }
        submitting = true
        Task {
            do {
                _ = try await QuizAPI.submit(quizId: quizId, answers: items)
                submitting = false
                submitSuccess = true
            } catch {
                submitting = false
                self.error = error.localizedDescription
            }
        }
    }
}
