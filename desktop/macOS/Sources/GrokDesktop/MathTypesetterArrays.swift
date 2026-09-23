import CoreGraphics

/// Matrices, `cases`, `aligned`/`gathered`, `array` and `\substack`.
extension MathTypesetter {
    private struct MathArrayMetrics {
        var cellStyle: MathStyle
        /// Strut height/depth (fractions of the cell font size) every row is padded to.
        var strutHeight: CGFloat
        var strutDepth: CGFloat
        /// Extra space between rows (ems of the surrounding text size).
        var rowGap: CGFloat
    }

    private func metrics(for kind: MathArrayKind, _ env: MathLayoutEnvironment) -> MathArrayMetrics {
        let level = env.style.level
        let textLevel = max(level, .text)
        // \baselineskip = 1.2em; array rows get a 0.7/0.3 strut of it (\arraystretch scales it).
        switch kind {
        case .matrix, .array:
            return MathArrayMetrics(cellStyle: MathStyle(level: textLevel, cramped: false),
                                    strutHeight: 0.84, strutDepth: 0.36, rowGap: 0)
        case .cases:
            return MathArrayMetrics(cellStyle: MathStyle(level: textLevel, cramped: false),
                                    strutHeight: 0.84 * 1.2, strutDepth: 0.36 * 1.2, rowGap: 0)
        case .displayCases:
            return MathArrayMetrics(cellStyle: level <= .text ? .display : MathStyle(level: level, cramped: false),
                                    strutHeight: 0.84 * 1.2, strutDepth: 0.36 * 1.2, rowGap: 0.15)
        case .smallMatrix:
            return MathArrayMetrics(cellStyle: MathStyle(level: max(level, .script), cramped: false),
                                    strutHeight: 0.6, strutDepth: 0.26, rowGap: 0)
        case .aligned, .gathered:
            // amsmath adds \jot (3pt) between display rows.
            return MathArrayMetrics(cellStyle: level <= .text ? .display : MathStyle(level: level, cramped: false),
                                    strutHeight: 0.84, strutDepth: 0.36, rowGap: 0.3)
        case .subarray:
            return MathArrayMetrics(cellStyle: MathStyle(level: level, cramped: env.style.cramped),
                                    strutHeight: 0.6, strutDepth: 0.26, rowGap: 0)
        }
    }

    private func alignment(_ array: MathArray, column j: Int) -> MathColumnAlignment {
        switch array.kind {
        case .matrix, .smallMatrix:
            return j < array.alignments.count ? array.alignments[j] : .center
        case .array, .subarray:
            if j < array.alignments.count { return array.alignments[j] }
            return array.alignments.last ?? .center
        case .cases, .displayCases:
            return .left
        case .aligned:
            return j % 2 == 0 ? .right : .left
        case .gathered:
            return .center
        }
    }

    /// Horizontal space before column j (j == count: after the last column), in ems.
    private func columnGaps(_ array: MathArray, count: Int) -> [CGFloat] {
        var gaps = [CGFloat](repeating: 0, count: count + 1)
        guard count > 0 else { return gaps }
        switch array.kind {
        case .matrix:
            for j in 1..<count { gaps[j] = 1 }  // 2 × \arraycolsep
        case .smallMatrix:
            for j in 1..<count { gaps[j] = 0.5556 }
        case .array:
            gaps[0] = 0.5
            gaps[count] = 0.5
            for j in 1..<count { gaps[j] = 1 }
        case .subarray:
            for j in 1..<count { gaps[j] = 0.5 }
        case .cases, .displayCases:
            for j in 1..<count { gaps[j] = 1 }  // \quad
        case .aligned:
            // Pairs of r/l columns; \minalignsep between pairs.
            for j in stride(from: 2, to: count, by: 2) { gaps[j] = 1 }
        case .gathered:
            break
        }
        return gaps
    }

    func arrayBox(_ array: MathArray, _ env: MathLayoutEnvironment) -> MathBox {
        let m = metrics(for: array.kind, env)
        let cellEnv = env.with(style: m.cellStyle)
        let cellSize = size(m.cellStyle)
        let textEm = size(MathStyle(level: max(env.style.level, .text), cramped: false))
        let cells = array.rows.map { row in row.map { layoutList($0, cellEnv) } }
        let columnCount = cells.map(\.count).max() ?? 0
        guard columnCount > 0, !cells.isEmpty else { return MathBox() }

        var columnWidths = [CGFloat](repeating: 0, count: columnCount)
        for row in cells {
            for (j, cell) in row.enumerated() { columnWidths[j] = max(columnWidths[j], cell.width) }
        }

        let ruleWidth = max(0.04 * textEm, 0.5)
        let doubleRuleSep = 0.2 * textEm

        // Horizontal layout, including vertical rules from the column spec.
        let gaps = columnGaps(array, count: columnCount)
        var columnX = [CGFloat](repeating: 0, count: columnCount)
        var verticalRuleX: [CGFloat] = []
        var x: CGFloat = 0
        func placeRules(_ n: Int) {
            for r in 0..<n {
                verticalRuleX.append(x)
                x += ruleWidth + (r < n - 1 ? doubleRuleSep : 0)
            }
        }
        for j in 0...columnCount {
            let gap = gaps[j] * textEm
            let rules = array.verticalRules[j] ?? 0
            if rules > 0 {
                if j == 0 {
                    placeRules(rules)
                    x += max(gap, 0.5 * textEm)
                } else if j == columnCount {
                    x += max(gap, 0.5 * textEm)
                    placeRules(rules)
                } else {
                    x += gap / 2
                    placeRules(rules)
                    x += gap / 2
                }
            } else {
                x += gap
            }
            if j < columnCount {
                columnX[j] = x
                x += columnWidths[j]
            }
        }
        let totalWidth = x

        // Vertical layout: rows padded to the strut, stacked top-down from y = 0.
        var baselines: [CGFloat] = []
        var horizontalRuleY: [CGFloat] = []
        var y: CGFloat = 0
        func placeHorizontalRules(_ n: Int) {
            for r in 0..<n {
                horizontalRuleY.append(y - ruleWidth)
                y -= ruleWidth + (r < n - 1 ? doubleRuleSep : 0)
            }
        }
        for (i, row) in cells.enumerated() {
            placeHorizontalRules(array.horizontalRules[i] ?? 0)
            let height = max(m.strutHeight * cellSize, row.map(\.height).max() ?? 0)
            let depth = max(m.strutDepth * cellSize, row.map(\.depth).max() ?? 0)
            let baseline = y - height
            baselines.append(baseline)
            y = baseline - depth
            if i < cells.count - 1 {
                y -= m.rowGap * textEm + (array.extraRowSpace[i] ?? 0) * textEm
            }
        }
        placeHorizontalRules(array.horizontalRules[cells.count] ?? 0)
        let totalHeight = -y

        // Center the whole array on the math axis (\vcenter).
        let shift = pt(k.axisHeight, env) + totalHeight / 2
        var children: [MathPlacedBox] = []
        for (i, row) in cells.enumerated() {
            for (j, cell) in row.enumerated() {
                let slack = columnWidths[j] - cell.width
                let dx: CGFloat
                switch alignment(array, column: j) {
                case .left: dx = 0
                case .center: dx = slack / 2
                case .right: dx = slack
                }
                children.append(MathPlacedBox(box: cell, x: columnX[j] + dx, y: baselines[i] + shift))
            }
        }
        for rx in verticalRuleX {
            let rule = MathBox(width: ruleWidth, height: totalHeight, depth: 0, content: .rule(env.color))
            children.append(MathPlacedBox(box: rule, x: rx, y: shift - totalHeight))
        }
        for ry in horizontalRuleY {
            let rule = MathBox(width: totalWidth, height: ruleWidth, depth: 0, content: .rule(env.color))
            children.append(MathPlacedBox(box: rule, x: 0, y: ry + shift))
        }
        let box = MathBox.group(children, width: totalWidth)
        box.height = max(box.height, shift)
        box.depth = max(box.depth, totalHeight - shift)
        return box
    }
}
