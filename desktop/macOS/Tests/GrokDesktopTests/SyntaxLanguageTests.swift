import XCTest
@testable import GrokDesktop

/// Key-token assertions per language.
final class SyntaxLanguageTests: XCTestCase {
    private func expect(_ needle: String, in code: String, _ lang: String, _ kind: SyntaxTokenKind?, occurrence: Int = 1, file: StaticString = #filePath, line: UInt = #line) {
        SyntaxTestSupport.assertKind(needle, in: code, lang, kind, occurrence: occurrence, file: file, line: line)
    }

    func testPython() {
        let code = #"""
        @decorator
        def greet(name: str) -> None:
            """Docstring here."""
            x = f"{name!r:>10} and {x}"  # comment
            y = 0x1F + 1_000 + 3.5e-2 + 2j
            if x is None and True: print(self.value, r"\d", b'\x00')
        class Foo(Base):
            match = 1
        match command:
            case "go": pass
        """#
        expect("@decorator", in: code, "python", .attribute)
        expect("def", in: code, "python", .keyword)
        expect("greet", in: code, "python", .function)
        expect("str", in: code, "python", .type)
        expect("\"\"\"Docstring here.\"\"\"", in: code, "python", .string)
        expect("f\"", in: code, "python", .string)
        expect("{", in: code, "python", .keyword)
        expect(":>10", in: code, "python", .string)
        expect("# comment", in: code, "python", .comment)
        expect("0x1F", in: code, "python", .number)
        expect("1_000", in: code, "python", .number)
        expect("3.5e-2", in: code, "python", .number)
        expect("2j", in: code, "python", .number)
        expect("None", in: code, "python", .constant, occurrence: 2)
        expect("True", in: code, "python", .constant)
        expect("print", in: code, "python", .function)
        expect("self", in: code, "python", .keyword)
        expect("r\"\\d\"", in: code, "python", .string)
        expect("\\x00", in: code, "python", .escape)
        expect("Foo", in: code, "python", .type)
        expect("match", in: code, "python", nil)
        expect("match", in: code, "python", .keyword, occurrence: 2)
        expect("case", in: code, "python", .keyword)
    }

    func testSwift() {
        let code = #"""
        import SwiftUI
        @State private var count: Int = 0 // note
        func run() async throws -> String? {
            let s = "Count: \(count + 1)\n"
            let raw = #"no \(interp) here"#
            #if DEBUG
            return nil
            #endif
            let closure = { $0 * 2 }
            return String(describing: self).uppercased()
        }
        /* nested /* comment */ still */
        """#
        expect("import", in: code, "swift", .keyword)
        expect("@State", in: code, "swift", .attribute)
        expect("Int", in: code, "swift", .type)
        expect("// note", in: code, "swift", .comment)
        expect("func", in: code, "swift", .keyword)
        expect("run", in: code, "swift", .function)
        expect("\\(", in: code, "swift", .keyword)
        expect("count", in: code, "swift", nil, occurrence: 3)
        expect("\\n", in: code, "swift", .escape)
        expect("#\"no \\(interp) here\"#", in: code, "swift", .string)
        expect("#if", in: code, "swift", .keyword)
        expect("nil", in: code, "swift", .constant)
        expect("$0", in: code, "swift", .variable)
        expect("String", in: code, "swift", .type, occurrence: 2)
        expect("uppercased", in: code, "swift", .function)
        expect("/* nested /* comment */ still */", in: code, "swift", .comment)
    }

    func testJavaScript() {
        let code = #"""
        const re = /ab+c/gi, half = total / 2;
        const msg = `Hello ${user.name}, you have ${count} items`;
        // line comment
        class A extends B { #secret = 1; get(key) { return this.#secret ?? null; } }
        console.log(msg, undefined, 10n);
        """#
        expect("const", in: code, "js", .keyword)
        expect("/ab+c/gi", in: code, "js", .regex)
        expect("/ 2", in: code, "js", nil)
        expect("`Hello ", in: code, "js", .string)
        expect("${", in: code, "js", .keyword)
        expect("user", in: code, "js", nil)
        expect(" items`", in: code, "js", .string)
        expect("// line comment", in: code, "js", .comment)
        expect("B", in: code, "js", .type)
        expect("#secret", in: code, "js", .variable)
        expect("get", in: code, "js", .function)
        expect("this", in: code, "js", .keyword)
        expect("null", in: code, "js", .constant)
        expect("log", in: code, "js", .function)
        expect("undefined", in: code, "js", .constant)
        expect("10n", in: code, "js", .number)
    }

    func testJSXAndTypeScriptGenerics() {
        let jsx = #"""
        const el = <div className="box" onClick={() => go(1)}>Hi {name}<Child /></div>;
        """#
        expect("div", in: jsx, "jsx", .tag)
        expect("className", in: jsx, "jsx", .attribute)
        expect("\"box\"", in: jsx, "jsx", .string)
        expect("go", in: jsx, "jsx", .function)
        expect("Hi", in: jsx, "jsx", nil)
        expect("Child", in: jsx, "jsx", .type)
        let ts = #"""
        const id = <T,>(value: T): T => value;
        function f<T extends string>(x: T): Array<T> { return [x]; }
        interface Props { type: string; readonly id: number }
        """#
        expect("T", in: ts, "ts", .type)
        expect("value", in: ts, "ts", nil)
        expect("string", in: ts, "ts", .type)
        expect("interface", in: ts, "ts", .keyword)
        expect("Props", in: ts, "ts", .type)
        expect("type", in: ts, "ts", nil)
        expect("readonly", in: ts, "ts", .keyword)
    }

    func testRust() {
        let code = #"""
        #[derive(Debug)]
        struct Wrapper<'a> { s: &'a str, c: char }
        fn main() {
            let c = 'x'; let nl = '\n'; let e = '😀';
            let raw = r#"raw "quoted""#;
            let n = 1_000u32 + 0xFFu8;
            println!("{}", raw);
            let s: &'static str = "hi";
        }
        """#
        expect("#[derive(Debug)]", in: code, "rust", .attribute)
        expect("Wrapper", in: code, "rust", .type)
        expect("'a", in: code, "rust", .keyword)
        expect("'a", in: code, "rust", .keyword, occurrence: 2)
        expect("str", in: code, "rust", .type)
        expect("'x'", in: code, "rust", .string)
        expect("\\n", in: code, "rust", .escape)
        expect("'😀'", in: code, "rust", .string)
        expect("r#\"raw \"quoted\"\"#", in: code, "rust", .string)
        expect("1_000u32", in: code, "rust", .number)
        expect("0xFFu8", in: code, "rust", .number)
        expect("println!", in: code, "rust", .function)
        expect("'static", in: code, "rust", .keyword)
        expect("main", in: code, "rust", .function)
    }

    func testGoAndC() {
        let go = "package main\nfunc (s *Server) Run() error {\n\traw := `C:\\path`\n\tfmt.Println(raw, nil, 'r')\n\treturn nil\n}\n"
        expect("func", in: go, "go", .keyword)
        expect("error", in: go, "go", .type)
        expect("`C:\\path`", in: go, "go", .string)
        expect("Println", in: go, "go", .function)
        expect("nil", in: go, "go", .constant)
        expect("'r'", in: go, "go", .string)
        let c = "#include <stdio.h>\n#define MAX 10\nint main(void) { char *p = NULL; printf(\"%d\\n\", MAX); return 0; }\n"
        expect("#include", in: c, "c", .attribute)
        expect("<stdio.h>", in: c, "c", .string)
        expect("#define", in: c, "c", .attribute)
        expect("MAX", in: c, "c", .constant)
        expect("int", in: c, "c", .type)
        expect("NULL", in: c, "c", .constant)
        expect("printf", in: c, "c", .function)
        expect("\\n", in: c, "c", .escape)
        let cpp = "auto s = R\"x(raw \"text\")x\"; std::vector<int> v{1'000'000}; template <typename T> class Box {};"
        expect("R\"x(raw \"text\")x\"", in: cpp, "c++", .string)
        expect("vector", in: cpp, "c++", .type)
        expect("1'000'000", in: cpp, "c++", .number)
        expect("template", in: cpp, "c++", .keyword)
        expect("Box", in: cpp, "c++", .type)
    }

    func testCSharpJavaKotlin() {
        let cs = #"""
        [Serializable]
        public class A { string p = @"C:\dir"; string q = $"Hi {name,5:F2}!"; var x = nameof(A); }
        """#
        expect("Serializable", in: cs, "cs", .attribute)
        expect("@\"C:\\dir\"", in: cs, "cs", .string)
        expect("$\"Hi ", in: cs, "cs", .string)
        expect("name", in: cs, "cs", nil)
        expect(":F2", in: cs, "cs", .string)
        expect("nameof", in: cs, "cs", .keyword)
        let java = "@Override\npublic String toString() { char c = 'x'; String t = \"\"\"\n  block\n  \"\"\"; return t; }"
        expect("@Override", in: java, "java", .attribute)
        expect("'x'", in: java, "java", .string)
        expect("block", in: java, "java", .string)
        expect("toString", in: java, "java", .function)
        let kt = "fun greet(name: String) = println(\"Hi $name, ${name.length} chars\")\nval data = 1"
        expect("fun", in: kt, "kotlin", .keyword)
        expect("greet", in: kt, "kotlin", .function)
        expect("$name", in: kt, "kotlin", .variable)
        expect("${", in: kt, "kotlin", .keyword)
        expect("length", in: kt, "kotlin", nil)
        expect("data", in: kt, "kotlin", nil)
    }

    func testRubyPHPPerl() {
        let rb = #"""
        class Foo < Bar
          attr_reader :name
          def initialize(name) = @name = name
          def greet
            puts "Hi #{@name}!" if name =~ /\w+/
            <<~EOS
              Hello #{name}
            EOS
          end
        end
        opts = { key: 1 }
        """#
        expect("class", in: rb, "ruby", .keyword)
        expect("Foo", in: rb, "ruby", .type)
        expect(":name", in: rb, "ruby", .constant)
        expect("@name", in: rb, "ruby", .variable)
        expect("greet", in: rb, "ruby", .function)
        expect("#{", in: rb, "ruby", .keyword)
        expect("/\\w+/", in: rb, "ruby", .regex)
        expect("<<~EOS", in: rb, "ruby", .string)
        expect("Hello ", in: rb, "ruby", .string)
        expect("#{", in: rb, "ruby", .keyword, occurrence: 2)
        expect("key:", in: rb, "ruby", .constant)
        let php = "<h1><?php echo $title; ?></h1>\n<?php\n// comment\n$x = \"Hi {$user->name} $y\";\nfunction f(): int { return 1; }\n"
        expect("h1", in: php, "php", .tag)
        expect("<?php", in: php, "php", .attribute)
        expect("echo", in: php, "php", .keyword)
        expect("$title", in: php, "php", .variable)
        expect("?>", in: php, "php", .attribute)
        expect("// comment", in: php, "php", .comment)
        expect("$y", in: php, "php", .variable)
        expect("f", in: php, "php", .function)
        let noTags = "$name = strtolower($input);"
        expect("$name", in: noTags, "php", .variable)
        expect("strtolower", in: noTags, "php", .function)
        let pl = "my %h = (a => 1);\nmy @a = qw(x y);\n$s =~ s/foo/bar/g;\nprint \"$h{a}\\n\";\n"
        expect("%h", in: pl, "perl", .variable)
        expect("qw(x y)", in: pl, "perl", .string)
        expect("s/foo/bar/g", in: pl, "perl", .regex)
        expect("print", in: pl, "perl", .function)
    }

    func testShell() {
        let sh = #"""
        #!/bin/bash
        # comment
        export PATH="$HOME/bin:$PATH"
        echo "args: $# $@ ${#arr[@]}" # trailing
        if [[ -f "$file" ]]; then
          npm install --save-dev typescript 2>&1 | tee log.txt
        fi
        for f in *.txt; do cat "$f"; done
        case "$1" in
          start|run) ./serve.sh ;;
        esac
        count=$((count + 1))
        cat <<'EOF'
        literal $NOT_VAR
        EOF
        """#
        expect("#!/bin/bash", in: sh, "bash", .comment)
        expect("# comment", in: sh, "bash", .comment)
        expect("export", in: sh, "bash", .keyword)
        expect("PATH", in: sh, "bash", .variable)
        expect("$HOME", in: sh, "bash", .variable)
        expect("echo", in: sh, "bash", .function)
        expect("$#", in: sh, "bash", .variable)
        expect("$@", in: sh, "bash", .variable)
        expect("${#arr[@]}", in: sh, "bash", .variable)
        expect("# trailing", in: sh, "bash", .comment)
        expect("if", in: sh, "bash", .keyword)
        expect("-f", in: sh, "bash", .attribute)
        expect("npm", in: sh, "bash", .function)
        expect("install", in: sh, "bash", nil)
        expect("--save-dev", in: sh, "bash", .attribute)
        expect("tee", in: sh, "bash", .function)
        expect("f", in: sh, "bash", .variable, occurrence: 3)
        expect("start", in: sh, "bash", nil)
        expect("./serve.sh", in: sh, "bash", .function)
        expect("esac", in: sh, "bash", .keyword)
        expect("count", in: sh, "bash", .variable)
        expect("literal $NOT_VAR", in: sh, "bash", .string)
        // `$#` must not start a comment; `a#b` is a word.
        let edge = "echo $#; echo a#b"
        expect("a#b", in: edge, "sh", nil)
        expect("$#", in: edge, "sh", .variable)
    }

    func testConsoleSession() {
        let session = "$ brew install ripgrep\n==> Downloading ripgrep\n% ls -la\ntotal 8\nuser@host:~/src$ git log --oneline\nabc123 First commit\n"
        expect("$", in: session, "console", .keyword)
        expect("brew", in: session, "console", .function)
        expect("--oneline", in: session, "console", .attribute)
        expect("==> Downloading ripgrep", in: session, "console", nil)
        expect("total 8", in: session, "console", nil)
        expect("ls", in: session, "console", .function)
        expect("abc123 First commit", in: session, "console", nil)
        expect("git", in: session, "console", .function)
        // No prompts at all: highlight as a script.
        expect("npm", in: "npm run dev\n", "shell-session", .function)
    }

    func testPowerShell() {
        let ps = #"""
        # comment
        $files = Get-ChildItem -Path $env:TEMP -Filter *.log
        if ($files.Count -gt 0) { Write-Host "Found $($files.Count) files" }
        [int]$n = 42
        <# block #>
        """#
        expect("# comment", in: ps, "powershell", .comment)
        expect("$files", in: ps, "powershell", .variable)
        expect("Get-ChildItem", in: ps, "powershell", .function)
        expect("-Path", in: ps, "powershell", .attribute)
        expect("$env:TEMP", in: ps, "powershell", .variable)
        expect("if", in: ps, "powershell", .keyword)
        expect("-gt", in: ps, "powershell", .keyword)
        expect("Write-Host", in: ps, "powershell", .function)
        expect("\"Found ", in: ps, "powershell", .string)
        expect("int", in: ps, "powershell", .type)
        expect("42", in: ps, "powershell", .number)
        expect("<# block #>", in: ps, "powershell", .comment)
    }

    func testSQL() {
        let sql = "-- report\nSELECT id, COUNT(*) FROM users u WHERE u.name LIKE 'A%' AND deleted IS NULL;\nselect * from t where x = 'it''s' /* c */;\nCREATE TABLE t (id INTEGER PRIMARY KEY, v VARCHAR(20));"
        expect("-- report", in: sql, "sql", .comment)
        expect("SELECT", in: sql, "sql", .keyword)
        expect("select", in: sql, "sql", .keyword)
        expect("from", in: sql, "sql", .keyword)
        expect("COUNT", in: sql, "sql", .function)
        expect("'A%'", in: sql, "sql", .string)
        expect("'it''s'", in: sql, "sql", .string)
        expect("NULL", in: sql, "sql", .constant)
        expect("/* c */", in: sql, "sql", .comment)
        expect("INTEGER", in: sql, "sql", .type)
        expect("VARCHAR", in: sql, "sql", .type)
        expect("users", in: sql, "sql", nil)
    }

    func testHTMLAndXML() {
        let html = #"""
        <!-- note -->
        <div class="a" id=main hidden>&copy; 2024</div>
        <script>const x = 1; // js</script>
        <style>.a { color: red; }</style>
        """#
        expect("<!-- note -->", in: html, "html", .comment)
        expect("div", in: html, "html", .tag)
        expect("class", in: html, "html", .attribute)
        expect("\"a\"", in: html, "html", .string)
        expect("main", in: html, "html", .string)
        expect("hidden", in: html, "html", .attribute)
        expect("&copy;", in: html, "html", .escape)
        expect("2024", in: html, "html", nil)
        expect("const", in: html, "html", .keyword)
        expect("// js", in: html, "html", .comment)
        expect("color", in: html, "html", .property)
        expect("script", in: html, "html", .tag, occurrence: 2)
        let xml = "<?xml version=\"1.0\"?>\n<svg:rect x=\"1\"/><![CDATA[ <raw> ]]>"
        expect("svg:rect", in: xml, "xml", .tag)
        expect("version", in: xml, "xml", .attribute)
        expect(" <raw> ", in: xml, "xml", .string)
    }

    func testCSS() {
        let css = "/* c */\n@media (max-width: 600px) {\n  .card > li:hover, #id { color: #fff; margin: -1.5em auto !important; font-family: \"Inter\", sans-serif; }\n}\n:root { --gap: 4px; width: calc(100% - var(--gap)); }"
        expect("/* c */", in: css, "css", .comment)
        expect("@media", in: css, "css", .keyword)
        expect("max-width", in: css, "css", .property)
        expect("600px", in: css, "css", .number)
        expect(".card", in: css, "css", .type)
        expect("li", in: css, "css", .tag)
        expect(":hover", in: css, "css", .keyword)
        expect("#id", in: css, "css", .constant)
        expect("color", in: css, "css", .property)
        expect("#fff", in: css, "css", .number)
        expect("-1.5em", in: css, "css", .number)
        expect("!important", in: css, "css", .keyword)
        expect("\"Inter\"", in: css, "css", .string)
        expect("--gap", in: css, "css", .variable)
        expect("calc", in: css, "css", .function)
        expect("100%", in: css, "css", .number)
        let scss = "$base: 4px;\n.btn { &:hover { padding: $base * 2; } @include rounded(8px); }"
        expect("$base", in: scss, "scss", .variable)
        expect("&", in: scss, "scss", .keyword)
        expect("@include", in: scss, "scss", .keyword)
        expect("rounded", in: scss, "scss", .function)
    }

    func testJSON() {
        let json = #"{"name": "x", "n": -1.5e3, "ok": true, "none": null, "list": ["a", 2], "esc": "a\nb"} // c"#
        expect("\"name\"", in: json, "json", .property)
        expect("\"x\"", in: json, "json", .string)
        expect("-1.5e3", in: json, "json", .number)
        expect("true", in: json, "json", .constant)
        expect("null", in: json, "json", .constant)
        expect("\"a\"", in: json, "json", .string)
        expect("\\n", in: json, "json", .escape)
        expect("// c", in: json, "jsonc", .comment)
        let json5 = "{ unquoted: 'single', hex: 0x1F, inf: Infinity, }"
        expect("unquoted", in: json5, "json5", .property)
        expect("'single'", in: json5, "json5", .string)
        expect("0x1F", in: json5, "json5", .number)
        expect("Infinity", in: json5, "json5", .constant)
    }

    func testYAML() {
        let yaml = #"""
        # comment
        name: my-app
        version: 1.2
        enabled: yes
        "quoted key": 'single'
        list:
          - item one
          - key: value # trailing
        anchors: &base
          a: 1
        ref: *base
        script: |
          echo "not a key: here"
          line two
        after: done
        url: http://example.com:8080/path
        tag: !!str 123
        """#
        expect("# comment", in: yaml, "yaml", .comment)
        expect("name", in: yaml, "yaml", .property)
        expect("my-app", in: yaml, "yaml", .string)
        expect("1.2", in: yaml, "yaml", .number)
        expect("yes", in: yaml, "yaml", .constant)
        expect("\"quoted key\"", in: yaml, "yaml", .property)
        expect("'single'", in: yaml, "yaml", .string)
        expect("item one", in: yaml, "yaml", .string)
        expect("key", in: yaml, "yaml", .property)
        expect("# trailing", in: yaml, "yaml", .comment)
        expect("&base", in: yaml, "yaml", .variable)
        expect("*base", in: yaml, "yaml", .variable)
        expect("|", in: yaml, "yaml", .keyword)
        expect("echo \"not a key: here\"", in: yaml, "yaml", .string)
        expect("after", in: yaml, "yaml", .property)
        expect("http://example.com:8080/path", in: yaml, "yaml", .string)
        expect("!!str", in: yaml, "yaml", .attribute)
    }

    func testTOMLAndINI() {
        let toml = "# c\n[server.http]\nport = 8080\nhost = \"0.0.0.0\"\nlist = [1, 2]\ninline = { a = true, b = 'x' }\nwhen = 1979-05-27T07:32:00Z\n\"quoted.key\" = 1\n"
        expect("# c", in: toml, "toml", .comment)
        expect("[server.http]", in: toml, "toml", .type)
        expect("port", in: toml, "toml", .property)
        expect("8080", in: toml, "toml", .number)
        expect("\"0.0.0.0\"", in: toml, "toml", .string)
        expect("a", in: toml, "toml", .property, occurrence: 1)
        expect("true", in: toml, "toml", .constant)
        expect("1979-05-27T07:32:00Z", in: toml, "toml", .number)
        expect("\"quoted.key\"", in: toml, "toml", .property)
        let ini = "; comment\n[section]\nkey=value\nnum = 42\n"
        expect("; comment", in: ini, "ini", .comment)
        expect("[section]", in: ini, "ini", .type)
        expect("key", in: ini, "ini", .property)
        expect("value", in: ini, "ini", .string)
        expect("42", in: ini, "ini", .number)
        let env = "export API_KEY=\"abc\"\nURL=${BASE}/x # c\n"
        expect("export", in: env, ".env", .keyword)
        expect("API_KEY", in: env, ".env", .property)
        expect("${BASE}", in: env, ".env", .variable)
        expect("# c", in: env, ".env", .comment)
    }

    func testMarkdown() {
        let md = #"""
        # Title
        Setext
        ======
        Text with **bold**, _em_, `code`, [link](https://x.y) and <https://auto.link>.
        - item
        1. first
        > quote
        ```python
        def f(): pass
        ```
        ***
        """#
        expect("# Title", in: md, "md", .heading)
        expect("Setext", in: md, "md", .heading)
        expect("**bold**", in: md, "md", .emphasis)
        expect("_em_", in: md, "md", .emphasis)
        expect("`code`", in: md, "md", .string)
        expect("[link]", in: md, "md", .string)
        expect("(https://x.y)", in: md, "md", .link)
        expect("<https://auto.link>", in: md, "md", .link)
        expect("-", in: md, "md", .keyword)
        expect("1.", in: md, "md", .keyword)
        expect(">", in: md, "md", .keyword, occurrence: 2)
        expect("def", in: md, "md", .keyword)
        expect("***", in: md, "md", .punctuation)
        expect("snake_case_word", in: "a snake_case_word b", "md", nil)
    }

    func testDiff() {
        let diff = "diff --git a/f b/f\nindex 1..2 100644\n--- a/f\n+++ b/f\n@@ -1,3 +1,3 @@ func main() {\n context\n-old line\n+new line\n--- not a header\n\\ No newline at end of file\n"
        expect("diff --git a/f b/f", in: diff, "diff", .keyword)
        expect("--- a/f", in: diff, "diff", .keyword)
        expect("+++ b/f", in: diff, "diff", .keyword)
        expect("@@ -1,3 +1,3 @@", in: diff, "diff", .attribute)
        expect(" context", in: diff, "diff", nil)
        expect("-old line", in: diff, "diff", .deleted)
        expect("+new line", in: diff, "diff", .inserted)
        expect("--- not a header", in: diff, "diff", .deleted)
        expect("\\ No newline at end of file", in: diff, "diff", .comment)
    }

    func testDockerfileAndMakefile() {
        let docker = "# base\nFROM python:3.12-slim AS base\nENV APP_HOME=/app\nRUN pip install -r requirements.txt && echo $APP_HOME\nCMD [\"python\", \"app.py\"]\n"
        expect("# base", in: docker, "dockerfile", .comment)
        expect("FROM", in: docker, "dockerfile", .keyword)
        expect("AS", in: docker, "dockerfile", .keyword)
        expect("APP_HOME", in: docker, "dockerfile", .variable)
        expect("pip", in: docker, "dockerfile", .function)
        expect("-r", in: docker, "dockerfile", .attribute)
        expect("$APP_HOME", in: docker, "dockerfile", .variable)
        expect("\"python\"", in: docker, "dockerfile", .string)
        let make = "CC := gcc\n.PHONY: all\nall: main.o\n\t$(CC) -o $@ $^ # link\n\t@echo \"done\"\nSRC = $(wildcard *.c)\n"
        expect("CC", in: make, "makefile", .variable)
        expect(".PHONY", in: make, "makefile", .keyword)
        expect("all", in: make, "makefile", .function, occurrence: 2)
        expect("$(CC)", in: make, "makefile", .variable)
        expect("$@", in: make, "makefile", .variable)
        expect("# link", in: make, "makefile", .comment)
        expect("echo", in: make, "makefile", .function)
        expect("wildcard", in: make, "makefile", .function)
    }

    func testScriptingMisc() {
        let lua = "-- c\nlocal t = { [[long]], nil }\n--[[ block ]]\nfunction t.f(x) return x end"
        expect("-- c", in: lua, "lua", .comment)
        expect("local", in: lua, "lua", .keyword)
        expect("[[long]]", in: lua, "lua", .string)
        expect("nil", in: lua, "lua", .constant)
        expect("--[[ block ]]", in: lua, "lua", .comment)
        expect("f", in: lua, "lua", .function)
        let r = "x <- c(1, 2L, NA) %>% sum(na.rm = TRUE) # c"
        expect("%>%", in: r, "r", .keyword)
        expect("2L", in: r, "r", .number)
        expect("NA", in: r, "r", .constant)
        expect("na.rm", in: r, "r", nil)
        expect("sum", in: r, "r", .function)
        let julia = "function f(x::Int) where T\n  s = \"v=$x $(x+1)\"\n  return :sym, x'\nend #= block =#"
        expect("function", in: julia, "julia", .keyword)
        expect("f", in: julia, "julia", .function)
        expect("$x", in: julia, "julia", .variable)
        expect(":sym", in: julia, "julia", .constant)
        expect("#= block =#", in: julia, "julia", .comment)
        let ex = "defmodule A.B do\n  @doc \"x\"\n  def f(x), do: {:ok, x}\n  def re, do: ~r/a+/i\nend"
        expect("defmodule", in: ex, "elixir", .keyword)
        expect("@doc", in: ex, "elixir", .attribute)
        expect(":ok", in: ex, "elixir", .constant)
        expect("do:", in: ex, "elixir", .constant)
        expect("~r/a+/i", in: ex, "elixir", .regex)
        let hs = "{-# LANGUAGE GADTs #-}\n-- c\nf :: Int -> Int\nf x' = x' + 1 {- block -}\nc = 'a'"
        expect("{-# LANGUAGE GADTs #-}", in: hs, "haskell", .attribute)
        expect("-- c", in: hs, "haskell", .comment)
        expect("f", in: hs, "haskell", .function)
        expect("Int", in: hs, "haskell", .type)
        expect("x'", in: hs, "haskell", nil)
        expect("{- block -}", in: hs, "haskell", .comment)
        expect("'a'", in: hs, "haskell", .string)
    }

    func testFunctionalAndSystems() {
        let clj = "; c\n(defn greet [name] (str \"Hi \" name :k))\n#_ (ignored)"
        expect("; c", in: clj, "clojure", .comment)
        expect("defn", in: clj, "clojure", .keyword)
        expect("greet", in: clj, "clojure", .function)
        expect("str", in: clj, "clojure", .function)
        expect(":k", in: clj, "clojure", .constant)
        let zig = "const std = @import(\"std\");\npub fn main() !void { const x: u8 = 0xff; }"
        expect("@import", in: zig, "zig", .function)
        expect("u8", in: zig, "zig", .type)
        expect("0xff", in: zig, "zig", .number)
        let ml = "let rec f x = (* c *) match x with | Some y -> y | None -> 0"
        expect("(* c *)", in: ml, "ocaml", .comment)
        expect("Some", in: ml, "ocaml", .type)
        let erl = "-module(m).\nf(X) -> ?LOG(X), ok."
        expect("-module", in: erl, "erlang", .attribute)
        expect("X", in: erl, "erlang", .variable)
        expect("?LOG", in: erl, "erlang", .constant)
        let asm = "; c\n_start:\n  mov rax, 0x1\n  syscall\n  movl %eax, $1 # att\n"
        expect("; c", in: asm, "asm", .comment)
        expect("_start:", in: asm, "asm", .function)
        expect("mov", in: asm, "asm", .keyword)
        expect("rax", in: asm, "asm", .variable)
        expect("0x1", in: asm, "asm", .number)
        expect("%eax", in: asm, "asm", .variable)
        expect("$1", in: asm, "asm", .number)
        expect("# att", in: asm, "asm", .comment)
        let arm = "  stp x29, x30, [sp, #-16]!  // save\n"
        expect("x29", in: arm, "arm64", .variable)
        expect("#-16", in: arm, "arm64", .number)
        expect("// save", in: arm, "arm64", .comment)
    }

    func testConfigAndSchemas() {
        let tf = "resource \"aws_s3_bucket\" \"b\" {\n  bucket = \"x-${var.env}\"\n  count = 2 # c\n}"
        expect("resource", in: tf, "terraform", .keyword)
        expect("bucket", in: tf, "terraform", .property)
        expect("\"aws_s3_bucket\"", in: tf, "terraform", .string)
        expect("${", in: tf, "terraform", .keyword)
        expect("var", in: tf, "terraform", .variable)
        expect("count", in: tf, "terraform", .property)
        let nix = "{ pkgs ? import <nixpkgs> {} }: let x = ''\n  echo ${x}\n''; in x"
        expect("<nixpkgs>", in: nix, "nix", .string)
        expect("let", in: nix, "nix", .keyword)
        expect("${", in: nix, "nix", .keyword)
        let gql = "query Q($id: ID!) { user(id: $id) @skip(if: false) { name } }"
        expect("query", in: gql, "graphql", .keyword)
        expect("$id", in: gql, "graphql", .variable)
        expect("@skip", in: gql, "graphql", .attribute)
        let proto = "message User { repeated string tags = 1; }"
        expect("message", in: proto, "proto", .keyword)
        expect("User", in: proto, "proto", .type)
        expect("string", in: proto, "proto", .type)
        let sol = "contract C { uint256 public x = 1 ether; function f() external { require(msg.sender != address(0)); } }"
        expect("contract", in: sol, "solidity", .keyword)
        expect("uint256", in: sol, "solidity", .type)
        expect("msg", in: sol, "solidity", .variable)
        let nginx = "server {\n  listen 80; # c\n  location ~ \\.php$ { fastcgi_pass $upstream; }\n}"
        expect("server", in: nginx, "nginx", .keyword)
        expect("listen", in: nginx, "nginx", .keyword)
        expect("80", in: nginx, "nginx", .number)
        expect("# c", in: nginx, "nginx", .comment)
        expect("\\.php$", in: nginx, "nginx", .regex)
        expect("$upstream", in: nginx, "nginx", .variable)
        let cmake = "set(VAR \"${OTHER} x\")\nif(WIN32)\nendif()"
        expect("set", in: cmake, "cmake", .function)
        expect("${OTHER}", in: cmake, "cmake", .variable)
        expect("if", in: cmake, "cmake", .keyword)
    }

    func testDocumentFormats() {
        let tex = "\\section{Intro} % c\nInline $a^2 + \\alpha$ and 100\\%."
        expect("\\section", in: tex, "latex", .keyword)
        expect("Intro", in: tex, "latex", .heading)
        expect("% c", in: tex, "latex", .comment)
        expect("\\alpha", in: tex, "latex", .keyword)
        expect("\\%", in: tex, "latex", .escape)
        let commit = "fix(ui): align buttons\n\nBody text\n# comment\nSigned-off-by: A <a@b.c>\n"
        expect("fix", in: commit, "gitcommit", .keyword)
        expect("align buttons", in: commit, "gitcommit", .heading)
        expect("# comment", in: commit, "gitcommit", .comment)
        expect("Signed-off-by:", in: commit, "gitcommit", .property)
        let rebase = "pick 1a2b3c Fix bug\n# comment\nexec make test\n"
        expect("pick", in: rebase, "git-rebase-todo", .keyword)
        expect("1a2b3c", in: rebase, "git-rebase-todo", .number)
        expect("make", in: rebase, "git-rebase-todo", .function)
        let regex = #"^(?:a|b)+\d{2,3}[^x-z]$"#
        expect("(?:", in: regex, "regex", .keyword)
        expect("\\d", in: regex, "regex", .escape)
        expect("{2,3}", in: regex, "regex", .number)
        let http = "GET /api HTTP/1.1\nAccept: application/json\n\n{\"a\": 1}"
        expect("GET", in: http, "http", .keyword)
        expect("Accept", in: http, "http", .property)
        expect("\"a\"", in: http, "http", .property)
    }

    func testMoreLanguages() {
        let dart = "@override\nWidget build(BuildContext c) => Text('Hi $name ${n + 1}');"
        expect("@override", in: dart, "dart", .attribute)
        expect("$name", in: dart, "dart", .variable)
        let scala = "val s = s\"x = $x ${y + 1}\"; def f(a: Int): Int = a"
        expect("s\"x = ", in: scala, "scala", .string)
        expect("$x", in: scala, "scala", .variable)
        expect("def", in: scala, "scala", .keyword)
        let objc = "@interface A : NSObject\n- (void)run:(int)x;\n@end\nNSString *s = @\"hi\";"
        expect("@interface", in: objc, "objc", .keyword)
        expect("run", in: objc, "objc", .function)
        expect("@\"hi\"", in: objc, "objc", .string)
        expect("@end", in: objc, "objc", .keyword)
        let vb = "' c\nDim x As Integer = 1\nIf x > 0 Then Console.WriteLine(\"hi\")"
        expect("' c", in: vb, "vb", .comment)
        expect("Dim", in: vb, "vb", .keyword)
        expect("Integer", in: vb, "vb", .type)
        let matlab = "% c\nA = [1 2]';\ns = 'str';"
        expect("% c", in: matlab, "matlab", .comment)
        expect("'str'", in: matlab, "matlab", .string)
        expect("]'", in: matlab, "matlab", nil)
        let fortran = "program p\n  ! c\n  if (x .and. .true.) print *, 'hi'\nend program"
        expect("! c", in: fortran, "fortran", .comment)
        expect(".and.", in: fortran, "fortran", .keyword)
        expect(".true.", in: fortran, "fortran", .constant)
        let vim = "\" comment\nlet g:x = 1\nnnoremap <leader>w :w<CR>"
        expect("\" comment", in: vim, "vim", .comment)
        expect("g:x", in: vim, "vim", .variable)
        expect("<leader>", in: vim, "vim", .constant)
        let groovy = "def name = \"x ${y}\"\nprintln 'single'"
        expect("def", in: groovy, "groovy", .keyword)
        expect("'single'", in: groovy, "groovy", .string)
        let fs = "[<EntryPoint>]\nlet main argv = printfn $\"{x}\" // c"
        expect("[<EntryPoint>]", in: fs, "fsharp", .attribute)
        expect("// c", in: fs, "fsharp", .comment)
        let batch = "@echo off\nREM comment\nset NAME=value\nif exist %NAME% goto :end\n:end"
        expect("REM comment", in: batch, "bat", .comment)
        expect("NAME", in: batch, "bat", .variable)
        expect("%NAME%", in: batch, "bat", .variable)
        expect(":end", in: batch, "bat", .function, occurrence: 2)
        let pycon = ">>> x = 1\n>>> print(x)\n1\n"
        expect(">>>", in: pycon, "pycon", .keyword)
        expect("print", in: pycon, "pycon", .function)
        expect("1\n", in: pycon, "pycon", nil)
        let vue = "<template><p :title=\"msg\">{{ count + 1 }}</p></template>"
        expect("p", in: vue, "vue", .tag)
        expect("{{", in: vue, "vue", .keyword)
        expect("1", in: vue, "vue", .number)
        let jinja = "{% if user %}Hi {{ user.name | upper }}{% endif %}{# c #}"
        expect("if", in: jinja, "jinja2", .keyword)
        expect("endif", in: jinja, "jinja2", .keyword)
        expect("{# c #}", in: jinja, "jinja2", .comment)
        let erb = "<p><%= @user.name %></p><%# c %>"
        expect("@user", in: erb, "erb", .variable)
        expect("<%# c %>", in: erb, "erb", .comment)
    }

    func testRegressionsFromReview() {
        // Shell: quoted assignment values keep command position; options after prefix commands.
        let sh = "FOO=\"a b\" ./run.sh --x\nif ! command -v jq >/dev/null; then sudo -E make; fi\ncase $x in\n  a|b) go ;;\nesac"
        expect("./run.sh", in: sh, "bash", .function)
        expect("-v", in: sh, "bash", .attribute)
        expect("jq", in: sh, "bash", .function)
        expect("-E", in: sh, "bash", .attribute)
        expect("make", in: sh, "bash", .function)
        expect("a|b", in: sh, "bash", nil)
        expect("go", in: sh, "bash", .function)
        // YAML: block scalar after a list dash.
        let yaml = "cmd:\n  - |\n    echo hi\n  - name: x"
        expect("|", in: yaml, "yaml", .keyword)
        expect("echo hi", in: yaml, "yaml", .string)
        expect("name", in: yaml, "yaml", .property)
        // Markdown: reference definitions and fences indented inside list items.
        let md = "[docs]: https://x.y\n1. Step\n   ```js\n   let a = 1;\n   ```\n"
        expect("[docs]:", in: md, "markdown", .link)
        expect("let", in: md, "markdown", .keyword)
        // AWK pattern at line start; Swift regex literal vs division.
        expect("/^#/", in: "{ x }\n/^#/ { next }", "awk", .regex)
        let swift = "let re = /\\d+/\nlet half = total / 2 / n"
        expect("/\\d+/", in: swift, "swift", .regex)
        expect("/ 2 /", in: swift, "swift", nil)
        // C#/Go: PascalCase members after a dot are not types.
        let cs = "var n = user.Name; Console.WriteLine(DateTime.Now);"
        expect("Name", in: cs, "csharp", nil)
        expect("Now", in: cs, "csharp", nil)
        expect("DateTime", in: cs, "csharp", .type)
        expect("WriteLine", in: cs, "csharp", .function)
        // SQL positional parameters; Apache directives.
        expect("$1", in: "WHERE id = $1", "sql", .variable)
        let apache = "RewriteEngine On\nRewriteCond %{HTTP_HOST} ^www\\. [NC]"
        expect("On", in: apache, "apache", .constant)
        expect("%{HTTP_HOST}", in: apache, "apache", .variable)
        expect("^www\\.", in: apache, "apache", .regex)
        // TypeScript contextual keywords used as names; JS method named `get`.
        let ts = "const type = 1; obj.set(k, v); declare module 'x' {}"
        expect("type", in: ts, "ts", nil)
        expect("declare", in: ts, "ts", .keyword)
        expect("module", in: ts, "ts", .keyword)
    }
}
