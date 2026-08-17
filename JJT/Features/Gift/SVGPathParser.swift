import SwiftUI

/// 迷你 SVG path 解析器（支撑 M/L/C/Z 及其小写相对形式 + 隐式重复命令），
/// 供 2D 礼物矢量渲染使用（对齐安卓 Compose PathParser 用法）
enum SVGPathParser {

    static func parse(_ d: String, scale k: CGFloat) -> Path {
        let tokens = tokenize(d)
        var path = Path()
        var i = 0
        var cmd: Character = "M"
        var cur = CGPoint.zero
        var start = CGPoint.zero

        func num() -> CGFloat {
            let v = Double(tokens[i]) ?? 0
            i += 1
            return CGFloat(v)
        }

        while i < tokens.count {
            if let c = tokens[i].first, tokens[i].count == 1, c.isLetter {
                cmd = c
                i += 1
                // Z/z 无参数
                if cmd == "Z" || cmd == "z" {
                    path.closeSubpath()
                    cur = start
                    continue
                }
            }
            let rel = cmd.isLowercase
            switch Character(cmd.uppercased()) {
            case "M":
                let x = num(), y = num()
                let pt = rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
                path.move(to: CGPoint(x: pt.x * k, y: pt.y * k))
                cur = pt
                start = pt
                cmd = rel ? "l" : "L"   // 后续隐式点对按 lineto
            case "L":
                let x = num(), y = num()
                let pt = rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
                path.addLine(to: CGPoint(x: pt.x * k, y: pt.y * k))
                cur = pt
            case "C":
                var c1 = CGPoint(x: num(), y: num())
                var c2 = CGPoint(x: num(), y: num())
                var end = CGPoint(x: num(), y: num())
                if rel {
                    c1 = CGPoint(x: cur.x + c1.x, y: cur.y + c1.y)
                    c2 = CGPoint(x: cur.x + c2.x, y: cur.y + c2.y)
                    end = CGPoint(x: cur.x + end.x, y: cur.y + end.y)
                }
                path.addCurve(to: CGPoint(x: end.x * k, y: end.y * k),
                              control1: CGPoint(x: c1.x * k, y: c1.y * k),
                              control2: CGPoint(x: c2.x * k, y: c2.y * k))
                cur = end
            default:
                i += 1   // 未支持的命令：跳过（这些素材里只有 M/L/C/Z）
            }
        }
        return path
    }

    private static func tokenize(_ d: String) -> [String] {
        let pattern = "[A-Za-z]|-?\\d*\\.?\\d+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = d as NSString
        return regex.matches(in: d, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }
}
