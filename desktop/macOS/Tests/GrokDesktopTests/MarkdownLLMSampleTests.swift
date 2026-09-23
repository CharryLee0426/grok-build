import XCTest
@testable import GrokDesktop

/// Realistic LLM responses with their complete expected trees.
final class MarkdownLLMSampleTests: MarkdownTestCase {
    func testSetupGuide() {
        let src = """
        ## Setting up the project

        To get started, follow these steps:

        1. **Clone the repository**
           ```bash
           git clone https://github.com/example/repo.git
           cd repo
           ```
        2. **Install dependencies**
           - Run `npm install`
           - If that fails, try `npm ci`
        3. **Configure** the environment:
           | Variable | Default | Description |
           |----------|:-------:|-------------|
           | `PORT` | `3000` | Server port |
           | `DEBUG` | `false` | Enables $\\log_2 n$ tracing |

        **Note:** The time complexity is $O(n \\log n)$, where $n$ is the input size.

        > [!TIP]
        > Use `--verbose` for more output.

        The final formula:

        $$
        T(n) = 2T\\left(\\frac{n}{2}\\right) + O(n)
        $$

        That's it!
        """
        let table = MarkdownBlock.table(MarkdownTable(
            alignments: [.none, .center, .none],
            header: [[t("Variable")], [t("Default")], [t("Description")]],
            rows: [
                [[code("PORT")], [code("3000")], [t("Server port")]],
                [[code("DEBUG")], [code("false")], [t("Enables "), math("\\log_2 n"), t(" tracing")]],
            ]
        ))
        assertParse(src, [
            h(2, t("Setting up the project")),
            p(t("To get started, follow these steps:")),
            ol(
                [p(strong(t("Clone the repository"))), fence("bash", "git clone https://github.com/example/repo.git\ncd repo")],
                [p(strong(t("Install dependencies"))), ul([p(t("Run "), code("npm install"))], [p(t("If that fails, try "), code("npm ci"))])],
                [p(strong(t("Configure")), t(" the environment:")), table]
            ),
            p(strong(t("Note:")), t(" The time complexity is "), math("O(n \\log n)"), t(", where "), math("n"), t(" is the input size.")),
            .callout(kind: "tip", title: nil, content: [p(t("Use "), code("--verbose"), t(" for more output."))]),
            p(t("The final formula:")),
            .math("T(n) = 2T\\left(\\frac{n}{2}\\right) + O(n)"),
            p(t("That's it!")),
        ])
    }

    func testReasoningWithBoldLabels() {
        let src = """
        **Step 1: Understand the problem**
        We need to find $x$ such that $x^2 = 4$.

        **Step 2: Solve**
        - Taking square roots: $x = \\pm 2$
        - Check: $(-2)^2 = 4$ ✓

        ### Answer
        The solutions are $x = 2$ and $x = -2$. It costs $5 to verify, or $10 with shipping.
        """
        assertParse(src, [
            p(strong(t("Step 1: Understand the problem")), soft, t("We need to find "), math("x"), t(" such that "), math("x^2 = 4"), t(".")),
            p(strong(t("Step 2: Solve"))),
            ul([p(t("Taking square roots: "), math("x = \\pm 2"))], [p(t("Check: "), math("(-2)^2 = 4"), t(" ✓"))]),
            h(3, t("Answer")),
            p(t("The solutions are "), math("x = 2"), t(" and "), math("x = -2"), t(". It costs $5 to verify, or $10 with shipping.")),
        ])
    }

    func testNestedStepsWithCode() {
        let src = """
        1. First step:
           * Sub point with `code`
           * Another sub point
             ```python
             def f(x):
                 return x * 2
             ```
        2. Second step
          - two-space nested bullet under a number
        10. Tenth
        """
        assertParse(src, [
            ol(
                [p(t("First step:")), ul([p(t("Sub point with "), code("code"))],
                                         [p(t("Another sub point")), fence("python", "def f(x):\n    return x * 2")])],
                [p(t("Second step")), ul([p(t("two-space nested bullet under a number"))])],
                [p(t("Tenth"))]
            ),
        ])
    }

    func testCodeHeavyAnswer() {
        let src = """
        Here's the fix:

        ```swift
        func greet(_ name: String) -> String {
            return "Hello, \\(name)!" // *not* emphasis, $not$ math
        }
        ```

        Then call `greet("World")` — it returns `"Hello, World!"`.

        ---

        *Hope this helps!*
        """
        assertParse(src, [
            p(t("Here's the fix:")),
            fence("swift", "func greet(_ name: String) -> String {\n    return \"Hello, \\(name)!\" // *not* emphasis, $not$ math\n}"),
            p(t("Then call "), code("greet(\"World\")"), t(" — it returns "), code("\"Hello, World!\""), t(".")),
            .thematicBreak,
            p(em(t("Hope this helps!"))),
        ])
    }

    func testStreamingPartialSampleNeverCrashesAndEndsEqual() {
        let src = MarkdownTestDocuments.mixed(bytes: 3_000)
        let cache = MarkdownDocumentCache()
        var prefix = ""
        for ch in src {
            prefix.append(ch)
            _ = cache.blocks(for: prefix)
        }
        XCTAssertEqual(cache.blocks(for: src), MarkdownParser.parse(src))
    }
}
