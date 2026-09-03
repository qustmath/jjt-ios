import SwiftUI
import PhotosUI

/// 银行卡管理 — 列表/删除 + 绑卡表单（对齐安卓 BankCardScreen）
struct BankCardView: View {

    var onBack: (() -> Void)? = nil

    @StateObject private var vm = BankCardViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showBindForm = false

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if vm.isLoading {
                    Spacer()
                    ProgressView().tint(Noir.gold)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            if vm.cards.isEmpty {
                                Text("暂未绑定银行卡")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.35))
                                    .padding(.vertical, 40)
                            } else {
                                ForEach(vm.cards) { card in
                                    cardRow(card)
                                }
                            }
                            Button { showBindForm = true } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 14))
                                    Text("添加银行卡")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(Noir.gold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                                    Noir.gold.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                }
            }
        }
        .jjtPageGestures()
        .onAppear { vm.load() }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("知道了") { vm.clearError() }
        } message: {
            Text(vm.error ?? "")
        }
        .confirmationDialog("删除该银行卡？", isPresented: Binding(
            get: { vm.pendingDelete != nil },
            set: { if !$0 { vm.pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let card = vm.pendingDelete {
                    vm.delete(card)
                    vm.pendingDelete = nil
                }
            }
            Button("取消", role: .cancel) { vm.pendingDelete = nil }
        }
        .fullScreenCover(isPresented: $showBindForm, onDismiss: { vm.load() }) {
            BankCardBindView()
        }
    }

    private var topBar: some View {
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
            Text("银行卡")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .tracking(4)
                .foregroundStyle(Noir.goldText)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func cardRow(_ card: BankCardInfo) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0x3D/255, green: 0x2B/255, blue: 0x0E/255),
                                                  Color(red: 0x14/255, green: 0x0D/255, blue: 0x04/255)],
                                         center: .center, startRadius: 0, endRadius: 28))
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Noir.goldLight.opacity(0.5), lineWidth: 1))
                Image(systemName: "building.columns")
                    .font(.system(size: 16))
                    .foregroundStyle(Noir.goldLight)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(card.bankName ?? "银行卡")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Noir.ivory)
                    if card.isDefault == true {
                        Text("默认")
                            .font(.system(size: 8))
                            .foregroundStyle(Noir.goldLight)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Noir.gold.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text("\(card.cardholder ?? "") · 尾号 \(card.cardNo?.suffix(4) ?? "----")")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Button { vm.pendingDelete = card } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Noir.noir2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Noir.hairlineGold, lineWidth: 1))
    }
}

// MARK: - 绑卡表单

struct BankCardBindView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var cardNo = ""
    @State private var bankName = ""
    @State private var cardholder = ""
    @State private var bankPhone = ""
    @State private var frontUrl: String?
    @State private var backUrl: String?
    @State private var frontItem: PhotosPickerItem?
    @State private var backItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var submitting = false
    @State private var error: String?

    private var valid: Bool {
        !cardNo.isEmpty && !bankName.isEmpty && !cardholder.isEmpty &&
        !bankPhone.isEmpty && frontUrl != nil && backUrl != nil
    }

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Noir.goldLight)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
                    }
                    Spacer()
                    Text("添加银行卡")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(Noir.goldText)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 12) {
                        TextField("卡号", text: $cardNo).keyboardType(.numberPad).noirField()
                        TextField("银行名称（如：招商银行）", text: $bankName).noirField()
                        TextField("持卡人姓名", text: $cardholder).noirField()
                        TextField("银行预留手机号", text: $bankPhone).keyboardType(.numberPad).noirField()

                        HStack(spacing: 12) {
                            photoPicker("卡面正面", url: frontUrl, item: $frontItem) { uploadPhoto($0) { frontUrl = $0 } }
                            photoPicker("卡面背面", url: backUrl, item: $backItem) { uploadPhoto($0) { backUrl = $0 } }
                        }

                        if uploading {
                            HStack(spacing: 8) {
                                ProgressView().tint(Noir.gold).scaleEffect(0.8)
                                Text("照片上传中…")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }

                        Button { submit() } label: {
                            Text(submitting ? "提交中…" : "确认绑定")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    valid
                                        ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0xD9/255, green: 0x04/255, blue: 0x29/255), Noir.crimsonDeep, Noir.wine],
                                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                                        : AnyShapeStyle(Color.white.opacity(0.08))
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!valid || submitting || uploading)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
        }
        .alert("提示", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("知道了") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .jjtPageGestures()
    }

    private func photoPicker(_ label: String, url: String?, item: Binding<PhotosPickerItem?>,
                             onPick: @escaping (PhotosPickerItem?) -> Void) -> some View {
        PhotosPicker(selection: item, matching: .images) {
            ZStack {
                if let url, let u = URL(string: url) {
                    AsyncImage(url: u) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Noir.noir3
                        }
                    }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "camera")
                            .font(.system(size: 20))
                            .foregroundStyle(Noir.gold.opacity(0.6))
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(Noir.noir2)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noir.hairlineGold, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onChange(of: item.wrappedValue) { _, v in onPick(v) }
    }

    private func uploadPhoto(_ item: PhotosPickerItem?, done: @escaping (String) -> Void) {
        guard let item else { return }
        uploading = true
        Task {
            defer { uploading = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data),
                      let jpeg = img.jpegData(compressionQuality: 0.82) else { return }
                let url = try await APIClient.shared.uploadFile(
                    data: jpeg, filename: "bankcard_\(Int(Date().timeIntervalSince1970)).jpg", mime: "image/jpeg")
                done(url)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func submit() {
        guard valid, !submitting else { return }
        submitting = true
        Task {
            do {
                _ = try await WithdrawAPI.bindCard(BindCardReq(
                    cardNo: cardNo, bankName: bankName, cardholder: cardholder,
                    bankPhone: bankPhone, cardFrontUrl: frontUrl!, cardBackUrl: backUrl!))
                jjtShowToast("银行卡绑定成功")
                dismiss()
            } catch {
                self.error = error.localizedDescription
                submitting = false
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class BankCardViewModel: ObservableObject {

    @Published var cards: [BankCardInfo] = []
    @Published var isLoading = true
    @Published var error: String?
    @Published var pendingDelete: BankCardInfo?

    func load() {
        Task {
            cards = (try? await WithdrawAPI.cards()) ?? []
            isLoading = false
        }
    }

    func delete(_ card: BankCardInfo) {
        Task {
            do {
                _ = try await WithdrawAPI.deleteCard(id: card.id)
                cards.removeAll { $0.id == card.id }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func clearError() { error = nil }
}
