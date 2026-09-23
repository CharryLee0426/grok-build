import Foundation

/// Realistic LLM-style Markdown used by the performance, streaming and fuzz tests.
enum MarkdownTestDocuments {
    static let fragments: [String] = [
        """
        ## Overview of step %d

        Here is a **short summary** with *emphasis*, `inline code`, a [link](https://example.com/docs?id=%d "Docs"), \
        and some math: $E = mc^2$ and $\\frac{a_%d}{b}$. Prices are $5 and $10, not math.
        Another line with ~~strikethrough~~ and a bare URL https://example.org/path_(x).

        """,
        """
        1. **Install the dependencies**
           - Run the installer
           - Check the version with `tool --version`
        2. **Configure** the project:
           ```bash
           export PATH="$HOME/bin:$PATH"
           make build -j%d
           ```
        3. Verify:
           $$
           \\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}
           $$

        """,
        """
        | Option | Type | Default | Notes |
        |:-------|:----:|--------:|-------|
        | `timeout` | `Int` | %d | seconds, see $t_{max}$ |
        | `retries` | `Int` | 3 | uses **exponential** backoff |
        | `mode` | `String` | "fast" | one of `fast`, `safe` |

        """,
        """
        > [!NOTE]
        > This is a callout with **bold** text and a list:
        > - item one
        > - item two

        > A plain quote spanning
        lazy continuation lines.

        """,
        """
        ```swift
        struct Point%d: Equatable {
            var x: Double
            var y: Double
            func distance(to other: Point%d) -> Double {
                ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
            }
        }
        ```

        """,
        """
        - [x] Write the parser
        - [ ] Add tests for item %d
          with a continuation line
        - [ ] Measure performance

        ---

        """,
        """
        **Note:** thinking about the problem, the key insight is that $f(x) = x^2$ grows quickly, \
        so for $n = %d$ we get a large value.
        Let me reconsider: if we apply \\(g(x) = \\log x\\) then the growth is slower.
        We could also write the formula as \\[ \\int_0^1 x\\,dx = \\tfrac{1}{2} \\] inline.
        Therefore the answer is **42**.

        """,
        """
        \\begin{align}
        a &= b + c \\\\
        d &= e + f_%d
        \\end{align}

        Text with a footnote[^1] and an image ![diagram](img/diagram%d.png).

        [^1]: The footnote text.

        """,
    ]

    /// Builds a document of at least `bytes` UTF-8 bytes by cycling through the fragments.
    static func mixed(bytes target: Int) -> String {
        var out = ""
        var i = 0
        while out.utf8.count < target {
            let fragment = fragments[i % fragments.count]
            out += fragment.replacingOccurrences(of: "%d", with: String(i))
            i += 1
        }
        return out
    }

    /// A long "thinking" paragraph without blank lines.
    static func thinking(lines: Int) -> String {
        var out = ""
        for i in 0..<lines {
            switch i % 5 {
            case 0: out += "Let me think about step \(i): the value of $x_\(i)$ depends on `config[\(i)]`.\n"
            case 1: out += "Hmm, maybe **this** approach is wrong because the cost is $\(i) per unit.\n"
            case 2: out += "Actually, we can compute it as \\(a + b = \(i)\\) and move on.\n"
            case 3: out += "So the next thing to check is whether the *cache* is warm.\n"
            default: out += "OK. Continuing with the analysis of item number \(i) in the list.\n"
            }
        }
        return out
    }
}
