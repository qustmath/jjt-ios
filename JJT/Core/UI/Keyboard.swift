import SwiftUI

/// 收起系统键盘
func jjtDismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

extension View {
    /// 键盘收回（iOS 常规做法）：
    /// 1. 滚动联动收起——列表/表单拖动时键盘随手势收回
    /// 2. 键盘顶部工具条「完成」按钮（数字键盘没有回车键时尤其需要）
    ///
    /// 加在含输入框页面的根容器上；挂在非滚动容器时 scrollDismissesKeyboard 为空操作，
    /// 工具条照常生效。已有键盘工具条的页面（发布帖/结算/地址编辑）不要重复加。
    @ViewBuilder
    func jjtKeyboardDismiss() -> some View {
        scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { jjtDismissKeyboard() }
                }
            }
    }
}
