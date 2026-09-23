import XCTest
@testable import GrokDesktop

final class SyntaxResolutionTests: XCTestCase {
    func testAliases() {
        let cases: [(String, String)] = [
            ("py", "python"), ("Python", "python"), ("python3", "python"), ("PY", "python"), ("ipython", "python"),
            ("js", "javascript"), ("JavaScript", "javascript"), ("node", "javascript"), ("mjs", "javascript"), ("cjs", "javascript"),
            ("jsx", "jsx"), ("ts", "typescript"), ("TypeScript", "typescript"), ("tsx", "tsx"), ("mts", "typescript"),
            ("sh", "bash"), ("shell", "bash"), ("bash", "bash"), ("zsh", "zsh"), ("fish", "fish"), ("ksh", "bash"),
            ("console", "console"), ("shell-session", "console"), ("terminal", "console"), ("sh-session", "console"),
            ("c++", "cpp"), ("cpp", "cpp"), ("C++", "cpp"), ("cxx", "cpp"), ("hpp", "cpp"), ("cc", "cpp"),
            ("c", "c"), ("h", "c"), ("objective-c", "objectivec"), ("objc", "objectivec"), ("obj-c", "objectivec"),
            ("objective-c++", "objectivecpp"), ("mm", "objectivecpp"),
            ("yml", "yaml"), ("yaml", "yaml"), ("dockerfile", "dockerfile"), ("Dockerfile", "dockerfile"), ("docker", "dockerfile"),
            ("jsonc", "jsonc"), ("json5", "json5"), ("json", "json"), ("jsonl", "jsonl"), ("geojson", "json"),
            ("html+erb", "erb"), ("erb", "erb"), ("rs", "rust"), ("rust", "rust"), ("golang", "go"), ("go", "go"),
            ("kt", "kotlin"), ("kts", "kotlin"), ("cs", "csharp"), ("c#", "csharp"), ("csharp", "csharp"),
            ("ps1", "powershell"), ("pwsh", "powershell"), ("powershell", "powershell"), ("tf", "terraform"), ("hcl", "hcl"),
            ("rb", "ruby"), ("ruby", "ruby"), ("php", "php"), ("sql", "sql"), ("postgresql", "sql"), ("mysql", "sql"),
            ("plpgsql", "sql"), ("tsql", "sql"), ("html", "html"), ("htm", "html"), ("xml", "xml"), ("svg", "svg"),
            ("plist", "plist"), ("css", "css"), ("scss", "scss"), ("sass", "sass"), ("less", "less"), ("toml", "toml"),
            ("ini", "ini"), ("cfg", "ini"), ("properties", "properties"), ("env", "dotenv"), (".env", "dotenv"),
            ("md", "markdown"), ("markdown", "markdown"), ("mdx", "markdown"), ("make", "makefile"), ("Makefile", "makefile"),
            ("cmake", "cmake"), ("lua", "lua"), ("r", "r"), ("R", "r"), ("dart", "dart"), ("hs", "haskell"),
            ("haskell", "haskell"), ("ex", "elixir"), ("exs", "elixir"), ("erl", "erlang"), ("pl", "perl"), ("perl", "perl"),
            ("jl", "julia"), ("zig", "zig"), ("nim", "nim"), ("ml", "ocaml"), ("fs", "fsharp"), ("f#", "fsharp"),
            ("clj", "clojure"), ("cljs", "clojure"), ("edn", "clojure"), ("lisp", "lisp"), ("scheme", "scheme"),
            ("rkt", "racket"), ("elisp", "elisp"), ("vim", "vim"), ("vimscript", "vim"), ("graphql", "graphql"),
            ("gql", "graphql"), ("proto", "protobuf"), ("protobuf", "protobuf"), ("nix", "nix"), ("sol", "solidity"),
            ("asm", "asm"), ("nasm", "asm"), ("x86asm", "asm"), ("arm64", "asm"), ("latex", "latex"), ("tex", "latex"),
            ("diff", "diff"), ("patch", "diff"), ("gitcommit", "gitcommit"), ("git-rebase-todo", "gitrebase"),
            ("regex", "regex"), ("matlab", "matlab"), ("octave", "octave"), ("f90", "fortran"), ("fortran", "fortran"),
            ("groovy", "groovy"), ("gradle", "gradle"), ("vb", "vb"), ("vbnet", "vb"), ("vba", "vb"), ("nginx", "nginx"),
            ("apache", "apache"), ("htaccess", "apache"), ("csv", "csv"), ("text", "plaintext"), ("txt", "plaintext"),
            ("plaintext", "plaintext"), ("bat", "batch"), ("cmd", "batch"), ("scala", "scala"), ("swift", "swift"),
            ("java", "java"), ("pycon", "pycon"), ("vue", "vue"), ("svelte", "svelte"), ("jinja2", "jinja"),
            ("django", "django"), ("handlebars", "handlebars"), ("hbs", "handlebars"), ("mermaid", "mermaid"),
            ("glsl", "glsl"), ("hlsl", "hlsl"), ("wgsl", "wgsl"), ("cuda", "cuda"), ("metal", "metal"), ("http", "http"),
            ("prisma", "prisma"), ("awk", "awk"), ("pascal", "pascal"), ("delphi", "pascal"), ("dot", "dot"),
            ("gitignore", "gitignore"), ("crystal", "crystal"), ("elm", "elm"), ("purescript", "purescript")
        ]
        XCTAssertGreaterThanOrEqual(cases.count, 80)
        for (alias, id) in cases {
            XCTAssertEqual(SyntaxHighlighter.language(for: alias)?.id, id, "alias \(alias)")
        }
    }

    func testFenceInfoParsing() {
        XCTAssertEqual(SyntaxHighlighter.language(for: "python {.line-numbers}")?.id, "python")
        XCTAssertEqual(SyntaxHighlighter.language(for: "js title=\"app.js\"")?.id, "javascript")
        XCTAssertEqual(SyntaxHighlighter.language(for: "  rust,ignore  ")?.id, "rust")
        XCTAssertEqual(SyntaxHighlighter.language(for: "{r setup, include=FALSE}")?.id, "r")
        XCTAssertEqual(SyntaxHighlighter.language(for: "{.python}")?.id, "python")
        XCTAssertEqual(SyntaxHighlighter.language(for: "language-swift")?.id, "swift")
        XCTAssertEqual(SyntaxHighlighter.language(for: "python:main.py")?.id, "python")
        XCTAssertEqual(SyntaxHighlighter.language(for: "src/main.rs")?.id, "rust")
        XCTAssertEqual(SyntaxHighlighter.language(for: "package.json")?.id, "json")
        XCTAssertEqual(SyntaxHighlighter.language(for: "Dockerfile.dev")?.id, "dockerfile")
        XCTAssertEqual(SyntaxHighlighter.language(for: "CMakeLists.txt")?.id, "cmake")
        XCTAssertEqual(SyntaxHighlighter.language(for: "diff-js")?.id, "diff")
        XCTAssertEqual(SyntaxHighlighter.language(for: "python3.11")?.id, "python")
        XCTAssertEqual(SyntaxHighlighter.language(for: "tsconfig.json")?.id, "jsonc")
        XCTAssertEqual(SyntaxHighlighter.language(for: "html+django")?.id, "django")
        XCTAssertEqual(SyntaxHighlighter.language(for: "vb.net")?.id, "vb")
        XCTAssertNil(SyntaxHighlighter.language(for: ""))
        XCTAssertNil(SyntaxHighlighter.language(for: "   "))
        XCTAssertNil(SyntaxHighlighter.language(for: "notalanguage"))
        XCTAssertNil(SyntaxHighlighter.language(for: "{.foo}"))
        XCTAssertEqual(SyntaxHighlighter.language(for: "c++")?.displayName, "C++")
        XCTAssertEqual(SyntaxHighlighter.language(for: "sh")?.displayName, "Bash")
        XCTAssertEqual(SyntaxHighlighter.language(for: "shell-session")?.displayName, "Shell Session")
    }

    func testEveryLanguageHasLexerAndResolvesById() {
        for entry in SyntaxLanguageRegistry.entries {
            XCTAssertEqual(SyntaxHighlighter.language(for: entry.id)?.id, entry.id, entry.id)
            XCTAssertNotNil(SyntaxLanguageRegistry.lexerKind(forId: entry.id), entry.id)
            if case .code(let spec) = entry.kind { XCTAssertNotNil(SyntaxSpecs.spec(spec), entry.id) }
            for alias in entry.aliases {
                XCTAssertNotNil(SyntaxHighlighter.language(for: alias), "\(entry.id) alias \(alias)")
            }
        }
        // Tokenizing through an alias id also works.
        XCTAssertFalse(SyntaxHighlighter.tokens("let x = 1", language: SyntaxLanguage(id: "js", displayName: "JS")).isEmpty)
        XCTAssertTrue(SyntaxHighlighter.tokens("let x = 1", language: SyntaxLanguage(id: "nope", displayName: "?")).isEmpty)
    }

    func testDetection() {
        func detect(_ code: String) -> String? { SyntaxHighlighter.detectLanguage(code)?.id }
        XCTAssertEqual(detect("{\n  \"name\": \"x\",\n  \"n\": 1\n}"), "json")
        XCTAssertEqual(detect("[{\"a\": 1}, {\"a\": 2}]"), "json")
        XCTAssertEqual(detect("$ npm install\nadded 3 packages\n$ npm test"), "console")
        XCTAssertEqual(detect("diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b"), "diff")
        XCTAssertEqual(detect("--- a/file.txt\n+++ b/file.txt\n@@ -1,2 +1,2 @@\n-old\n+new"), "diff")
        XCTAssertEqual(detect("@@ -10,3 +10,4 @@\n context\n+added"), "diff")
        XCTAssertEqual(detect("<!DOCTYPE html>\n<html><body></body></html>"), "html")
        XCTAssertEqual(detect("<div class=\"x\">\n  <p>Hi</p>\n</div>"), "html")
        XCTAssertEqual(detect("<?xml version=\"1.0\"?>\n<root/>"), "xml")
        XCTAssertEqual(detect("<project>\n  <modelVersion>4.0.0</modelVersion>\n</project>"), "xml")
        XCTAssertEqual(detect("def main():\n    print(\"hi\")\n\nif __name__ == \"__main__\":\n    main()"), "python")
        XCTAssertEqual(detect("import os\nimport sys\n\nfor f in os.listdir('.'):\n    print(f)"), "python")
        XCTAssertEqual(detect("from pathlib import Path\nprint(Path.cwd())"), "python")
        XCTAssertEqual(detect("#!/usr/bin/env python3\nprint(1)"), "python")
        XCTAssertEqual(detect("#!/bin/bash\necho hi"), "bash")
        XCTAssertEqual(detect("npm install\nnpm run dev"), "bash")
        XCTAssertEqual(detect("cd my-app\ngit init\ngit add ."), "bash")
        XCTAssertEqual(detect("brew install --cask visual-studio-code"), "bash")
        XCTAssertEqual(detect("import SwiftUI\n\nstruct ContentView: View {\n    var body: some View { Text(\"Hi\") }\n}"), "swift")
        XCTAssertEqual(detect("fn main() {\n    let mut v = Vec::new();\n    println!(\"{:?}\", v);\n}"), "rust")
        XCTAssertEqual(detect("package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(\"hi\")\n}"), "go")
        XCTAssertEqual(detect("#include <iostream>\nint main() { std::cout << 1; }"), "cpp")
        XCTAssertEqual(detect("#include <stdio.h>\nint main(void) { printf(\"hi\"); return 0; }"), "c")
        XCTAssertEqual(detect("public class Main {\n  public static void main(String[] args) {\n    System.out.println(1);\n  }\n}"), "java")
        XCTAssertEqual(detect("using System;\nConsole.WriteLine(\"hi\");"), "csharp")
        XCTAssertEqual(detect("const x = require('fs');\nconsole.log(x);"), "javascript")
        XCTAssertEqual(detect("import React from 'react';\nexport default function App() {\n  return null;\n}"), "javascript")
        XCTAssertEqual(detect("interface User {\n  name: string;\n  age: number;\n}\nconst u: User = { name: 'a', age: 1 };"), "typescript")
        XCTAssertEqual(detect("SELECT id, name\nFROM users\nWHERE active = 1;"), "sql")
        XCTAssertEqual(detect("FROM node:20\nWORKDIR /app\nRUN npm ci"), "dockerfile")
        XCTAssertEqual(detect("name: CI\non:\n  push:\n    branches: [main]\njobs:\n  build:\n    runs-on: ubuntu-latest"), "yaml")
        XCTAssertEqual(detect("[package]\nname = \"x\"\nversion = \"0.1.0\"\n\n[dependencies]\nserde = \"1\""), "toml")
        XCTAssertEqual(detect("<?php\necho 'hi';"), "php")
        XCTAssertEqual(detect(">>> 1 + 1\n2"), "pycon")
        XCTAssertEqual(detect(".btn {\n  color: red;\n  padding: 4px;\n}"), "css")
        XCTAssertEqual(detect("## Heading\n\nSome text with a [link](https://x.y).\n\n- item"), "markdown")
        XCTAssertEqual(detect("Get-ChildItem -Path C:\\ | Where-Object { $_.Length -gt 1 }\nWrite-Host \"done\""), "powershell")

        // Conservative: prose, output, and ambiguous one-liners stay undetected.
        XCTAssertNil(detect("This is just a sentence explaining something."))
        XCTAssertNil(detect("Hello world\nSecond line of output\n42"))
        XCTAssertNil(detect("x = 1"))
        XCTAssertNil(detect(""))
        XCTAssertNil(detect("   \n  "))
        XCTAssertNil(detect("total 48\ndrwxr-xr-x  5 user  staff  160 Jan  1 12:00 dir"))
        XCTAssertNil(detect("[section]"))
    }
}
