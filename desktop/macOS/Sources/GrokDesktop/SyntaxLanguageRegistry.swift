import Foundation

enum SyntaxMarkupFlavor { case html, xml, vue, svelte, erb, ejs, eex, mustache }
enum SyntaxCSSFlavor { case css, scss, sass, less }
enum SyntaxJSONFlavor { case json, jsonc, json5 }
enum SyntaxINIFlavor { case ini, properties, dotenv }
enum SyntaxShellFlavor { case bash, zsh, fish, make }
enum SyntaxLispFlavor { case clojure, commonLisp, scheme, racket, elisp }

/// Which lexer handles a language.
enum SyntaxLexerKind: Equatable {
    case none
    case code(String)
    case markup(SyntaxMarkupFlavor)
    case php
    case css(SyntaxCSSFlavor)
    case json(SyntaxJSONFlavor)
    case yaml, toml
    case ini(SyntaxINIFlavor)
    case markdown, diff, gitCommit, gitRebase, regex, http, latex
    case shell(SyntaxShellFlavor)
    case console, pycon, powershell, batch, dockerfile, makefile
    case lisp(SyntaxLispFlavor)
    case asm, nginx, apache
}

struct SyntaxLanguageEntry {
    let id: String
    let name: String
    let kind: SyntaxLexerKind
    let aliases: [String]

    var language: SyntaxLanguage { SyntaxLanguage(id: id, displayName: name) }
}

enum SyntaxLanguageRegistry {
    static let entries: [SyntaxLanguageEntry] = [
        SyntaxLanguageEntry(id: "plaintext", name: "Text", kind: .none, aliases: ["text", "txt", "plain", "none", "nohighlight", "no-highlight", "output", "stdout", "stderr", "raw", "ascii", "ansi", "terminal-output", "plain-text"]),
        SyntaxLanguageEntry(id: "log", name: "Log", kind: .none, aliases: ["logs", "logfile"]),
        SyntaxLanguageEntry(id: "csv", name: "CSV", kind: .none, aliases: ["psv"]),
        SyntaxLanguageEntry(id: "tsv", name: "TSV", kind: .none, aliases: ["tab"]),
        SyntaxLanguageEntry(id: "swift", name: "Swift", kind: .code("swift"), aliases: ["swiftui", "swift5", "swift6"]),
        SyntaxLanguageEntry(id: "python", name: "Python", kind: .code("python"), aliases: ["py", "python3", "py3", "python2", "py2", "pyw", "pyi", "ipython", "ipython3", "jython", "gyp", "sage", "pyx", "cython", "pypy", "rpy"]),
        SyntaxLanguageEntry(id: "pycon", name: "Python Console", kind: .pycon, aliases: ["python-repl", "pyrepl", "python-console", "py-repl", "pytb", "python-traceback", "py-console", "python-session", "doctest"]),
        SyntaxLanguageEntry(id: "starlark", name: "Starlark", kind: .code("python"), aliases: ["bazel", "bzl", "sky", "build.bazel", "tiltfile", "workspace.bazel"]),
        SyntaxLanguageEntry(id: "mojo", name: "Mojo", kind: .code("python"), aliases: []),
        SyntaxLanguageEntry(id: "javascript", name: "JavaScript", kind: .code("javascript"), aliases: ["js", "mjs", "cjs", "node", "nodejs", "es", "es6", "es2015", "ecmascript", "jscript", "gjs", "javascriptreact"]),
        SyntaxLanguageEntry(id: "jsx", name: "JSX", kind: .code("javascript"), aliases: ["react", "react-jsx"]),
        SyntaxLanguageEntry(id: "typescript", name: "TypeScript", kind: .code("typescript"), aliases: ["ts", "mts", "cts", "deno"]),
        SyntaxLanguageEntry(id: "tsx", name: "TSX", kind: .code("typescript"), aliases: ["typescriptreact", "react-tsx"]),
        SyntaxLanguageEntry(id: "json", name: "JSON", kind: .json(.json), aliases: ["geojson", "topojson", "webmanifest", "har", "jsonld", "json-ld", "ipynb", "avsc", "sarif", "gltf", "babelrc", "eslintrc", "prettierrc", "package.json", "composer.json", "mcmeta"]),
        SyntaxLanguageEntry(id: "jsonc", name: "JSON with Comments", kind: .json(.jsonc), aliases: ["json-with-comments", "jsonwithcomments", "tsconfig", "jsconfig", "code-workspace", "tsconfig.json", "jsconfig.json", "devcontainer.json", "settings.json"]),
        SyntaxLanguageEntry(id: "json5", name: "JSON5", kind: .json(.json5), aliases: ["hjson"]),
        SyntaxLanguageEntry(id: "jsonl", name: "JSON Lines", kind: .json(.json), aliases: ["ndjson", "jsonlines", "json-lines"]),
        SyntaxLanguageEntry(id: "rust", name: "Rust", kind: .code("rust"), aliases: ["rs", "rustlang", "ron"]),
        SyntaxLanguageEntry(id: "go", name: "Go", kind: .code("go"), aliases: ["golang"]),
        SyntaxLanguageEntry(id: "c", name: "C", kind: .code("c"), aliases: ["h", "ansi-c", "c89", "c99", "c11", "c17", "c23"]),
        SyntaxLanguageEntry(id: "cpp", name: "C++", kind: .code("cpp"), aliases: ["c++", "cxx", "cc", "hpp", "hh", "hxx", "h++", "cplusplus", "cplus", "ino", "arduino", "ipp", "tpp", "cppm", "ixx", "c++17", "c++20", "cpp17", "cpp20"]),
        SyntaxLanguageEntry(id: "objectivec", name: "Objective-C", kind: .code("objectivec"), aliases: ["objective-c", "objc", "obj-c", "m", "objectivec2"]),
        SyntaxLanguageEntry(id: "objectivecpp", name: "Objective-C++", kind: .code("objectivecpp"), aliases: ["objective-c++", "objc++", "obj-c++", "objcpp", "mm"]),
        SyntaxLanguageEntry(id: "csharp", name: "C#", kind: .code("csharp"), aliases: ["cs", "c#", "c-sharp", "dotnet", "csx", "cake", "unity"]),
        SyntaxLanguageEntry(id: "java", name: "Java", kind: .code("java"), aliases: ["jsh", "jshell"]),
        SyntaxLanguageEntry(id: "kotlin", name: "Kotlin", kind: .code("kotlin"), aliases: ["kt", "kts", "ktm", "gradle.kts", "build.gradle.kts"]),
        SyntaxLanguageEntry(id: "scala", name: "Scala", kind: .code("scala"), aliases: ["sc", "sbt"]),
        SyntaxLanguageEntry(id: "groovy", name: "Groovy", kind: .code("groovy"), aliases: ["gvy", "gy", "gsh", "jenkinsfile", "jenkins", "nextflow", "nf"]),
        SyntaxLanguageEntry(id: "gradle", name: "Gradle", kind: .code("groovy"), aliases: ["build.gradle", "settings.gradle"]),
        SyntaxLanguageEntry(id: "dart", name: "Dart", kind: .code("dart"), aliases: ["flutter"]),
        SyntaxLanguageEntry(id: "ruby", name: "Ruby", kind: .code("ruby"), aliases: ["rb", "jruby", "gemfile", "podfile", "rake", "rakefile", "gemspec", "ru", "irb", "rbw", "vagrantfile", "fastfile", "brewfile", "appfile", "thor", "jbuilder", "rabl", "capfile", "rails"]),
        SyntaxLanguageEntry(id: "crystal", name: "Crystal", kind: .code("ruby"), aliases: ["cr"]),
        SyntaxLanguageEntry(id: "php", name: "PHP", kind: .php, aliases: ["php3", "php4", "php5", "php7", "php8", "phtml", "laravel", "blade"]),
        SyntaxLanguageEntry(id: "perl", name: "Perl", kind: .code("perl"), aliases: ["pl", "pm", "perl5", "plx", "pod", "cgi"]),
        SyntaxLanguageEntry(id: "raku", name: "Raku", kind: .code("perl"), aliases: ["perl6", "p6", "rakumod"]),
        SyntaxLanguageEntry(id: "lua", name: "Lua", kind: .code("lua"), aliases: ["luau", "rockspec", "roblox"]),
        SyntaxLanguageEntry(id: "r", name: "R", kind: .code("r"), aliases: ["rscript", "splus", "rprofile", "rlang"]),
        SyntaxLanguageEntry(id: "julia", name: "Julia", kind: .code("julia"), aliases: ["jl"]),
        SyntaxLanguageEntry(id: "haskell", name: "Haskell", kind: .code("haskell"), aliases: ["hs", "hsc", "ghc", "hs-boot"]),
        SyntaxLanguageEntry(id: "purescript", name: "PureScript", kind: .code("haskell"), aliases: ["purs"]),
        SyntaxLanguageEntry(id: "elm", name: "Elm", kind: .code("elm"), aliases: []),
        SyntaxLanguageEntry(id: "ocaml", name: "OCaml", kind: .code("ocaml"), aliases: ["ml", "mli", "mll", "mly", "reasonml"]),
        SyntaxLanguageEntry(id: "fsharp", name: "F#", kind: .code("fsharp"), aliases: ["fs", "fsi", "fsx", "f#", "fsscript", "f-sharp"]),
        SyntaxLanguageEntry(id: "elixir", name: "Elixir", kind: .code("elixir"), aliases: ["ex", "exs", "iex", "mix"]),
        SyntaxLanguageEntry(id: "erlang", name: "Erlang", kind: .code("erlang"), aliases: ["erl", "hrl", "escript", "app.src"]),
        SyntaxLanguageEntry(id: "zig", name: "Zig", kind: .code("zig"), aliases: ["zon"]),
        SyntaxLanguageEntry(id: "nim", name: "Nim", kind: .code("nim"), aliases: ["nims", "nimble"]),
        SyntaxLanguageEntry(id: "solidity", name: "Solidity", kind: .code("solidity"), aliases: ["sol"]),
        SyntaxLanguageEntry(id: "graphql", name: "GraphQL", kind: .code("graphql"), aliases: ["gql", "graphqls"]),
        SyntaxLanguageEntry(id: "protobuf", name: "Protocol Buffers", kind: .code("protobuf"), aliases: ["proto", "proto3", "proto2", "protocol-buffers"]),
        SyntaxLanguageEntry(id: "terraform", name: "Terraform", kind: .code("hcl"), aliases: ["tf", "tfvars", "tfstack", "opentofu", "tofu"]),
        SyntaxLanguageEntry(id: "hcl", name: "HCL", kind: .code("hcl"), aliases: ["hcl2", "nomad", "packer", "sentinel"]),
        SyntaxLanguageEntry(id: "nix", name: "Nix", kind: .code("nix"), aliases: ["nixos", "flake.nix"]),
        SyntaxLanguageEntry(id: "sql", name: "SQL", kind: .code("sql"), aliases: ["mysql", "postgresql", "postgres", "psql", "pgsql", "plsql", "plpgsql", "sqlite", "sqlite3", "tsql", "t-sql", "mssql", "sqlserver", "mariadb", "bigquery", "snowflake", "hive", "hql", "sparksql", "spark-sql", "redshift", "clickhouse", "oracle", "db2", "duckdb", "trino", "presto", "athena", "cql", "sqlx", "pls", "ddl", "dml"]),
        SyntaxLanguageEntry(id: "matlab", name: "MATLAB", kind: .code("matlab"), aliases: []),
        SyntaxLanguageEntry(id: "octave", name: "Octave", kind: .code("matlab"), aliases: []),
        SyntaxLanguageEntry(id: "fortran", name: "Fortran", kind: .code("fortran"), aliases: ["f90", "f95", "f03", "f08", "f77", "f", "for", "ftn", "fortran90", "fortran77", "fpp"]),
        SyntaxLanguageEntry(id: "vb", name: "Visual Basic", kind: .code("vb"), aliases: ["vbnet", "vb.net", "visualbasic", "visual-basic", "vba", "vbs", "vbscript", "bas", "vb6"]),
        SyntaxLanguageEntry(id: "pascal", name: "Pascal", kind: .code("pascal"), aliases: ["delphi", "pas", "dpr", "objectpascal", "object-pascal", "lpr", "freepascal", "lazarus"]),
        SyntaxLanguageEntry(id: "awk", name: "AWK", kind: .code("awk"), aliases: ["gawk", "mawk", "nawk"]),
        SyntaxLanguageEntry(id: "cmake", name: "CMake", kind: .code("cmake"), aliases: ["cmakelists", "cmakelists.txt"]),
        SyntaxLanguageEntry(id: "vim", name: "Vim Script", kind: .code("vim"), aliases: ["vimscript", "viml", "vimrc", "nvim", "exrc", "gvimrc", "vim9", "vim9script"]),
        SyntaxLanguageEntry(id: "glsl", name: "GLSL", kind: .code("glsl"), aliases: ["vert", "frag", "geom", "tesc", "tese", "comp", "vsh", "fsh", "shader", "opengl"]),
        SyntaxLanguageEntry(id: "hlsl", name: "HLSL", kind: .code("hlsl"), aliases: ["fx", "fxh", "hlsli", "cginc", "shaderlab"]),
        SyntaxLanguageEntry(id: "wgsl", name: "WGSL", kind: .code("wgsl"), aliases: ["webgpu"]),
        SyntaxLanguageEntry(id: "metal", name: "Metal", kind: .code("cuda"), aliases: ["msl"]),
        SyntaxLanguageEntry(id: "cuda", name: "CUDA", kind: .code("cuda"), aliases: ["cu", "cuh"]),
        SyntaxLanguageEntry(id: "prisma", name: "Prisma", kind: .code("prisma"), aliases: []),
        SyntaxLanguageEntry(id: "mermaid", name: "Mermaid", kind: .code("mermaid"), aliases: ["mmd"]),
        SyntaxLanguageEntry(id: "dot", name: "Graphviz", kind: .code("dot"), aliases: ["graphviz", "gv", "digraph"]),
        SyntaxLanguageEntry(id: "gitignore", name: ".gitignore", kind: .code("gitignore"), aliases: [".gitignore", "ignore", "dockerignore", ".dockerignore", "npmignore", "gitattributes", "hgignore", "eslintignore", "prettierignore", "codeowners"]),
        SyntaxLanguageEntry(id: "html", name: "HTML", kind: .markup(.html), aliases: ["htm", "xhtml", "html5", "shtml", "xht", "mhtml", "angular", "webc"]),
        SyntaxLanguageEntry(id: "xml", name: "XML", kind: .markup(.xml), aliases: ["xsd", "xsl", "xslt", "rss", "atom", "wsdl", "xaml", "axaml", "csproj", "fsproj", "vbproj", "vcxproj", "storyboard", "xib", "targets", "pom", "pom.xml", "resx", "kml", "gpx", "mathml", "opml", "tei", "nuspec", "xul", "rdf", "wxs", "ttml", "xliff", "xlf", "android", "androidmanifest", "sitemap", "fxml", "jelly", "dita"]),
        SyntaxLanguageEntry(id: "svg", name: "SVG", kind: .markup(.xml), aliases: []),
        SyntaxLanguageEntry(id: "plist", name: "Property List", kind: .markup(.xml), aliases: ["xmlplist", "entitlements", "info.plist"]),
        SyntaxLanguageEntry(id: "vue", name: "Vue", kind: .markup(.vue), aliases: ["vuejs", "nuxt"]),
        SyntaxLanguageEntry(id: "svelte", name: "Svelte", kind: .markup(.svelte), aliases: ["sveltekit"]),
        SyntaxLanguageEntry(id: "erb", name: "ERB", kind: .markup(.erb), aliases: ["html+erb", "rhtml", "eruby", "html.erb"]),
        SyntaxLanguageEntry(id: "ejs", name: "EJS", kind: .markup(.ejs), aliases: ["html+ejs"]),
        SyntaxLanguageEntry(id: "eex", name: "EEx", kind: .markup(.eex), aliases: ["heex", "leex", "html+eex", "html-eex", "surface"]),
        SyntaxLanguageEntry(id: "jinja", name: "Jinja", kind: .markup(.mustache), aliases: ["jinja2", "j2", "nunjucks", "njk", "html+jinja", "jinja-html"]),
        SyntaxLanguageEntry(id: "django", name: "Django", kind: .markup(.mustache), aliases: ["htmldjango", "html+django", "djangotemplate", "django-html"]),
        SyntaxLanguageEntry(id: "twig", name: "Twig", kind: .markup(.mustache), aliases: ["html+twig"]),
        SyntaxLanguageEntry(id: "liquid", name: "Liquid", kind: .markup(.mustache), aliases: ["html+liquid", "jekyll", "shopify"]),
        SyntaxLanguageEntry(id: "handlebars", name: "Handlebars", kind: .markup(.mustache), aliases: ["hbs", "mustache", "html+handlebars", "htmlbars", "ractive"]),
        SyntaxLanguageEntry(id: "css", name: "CSS", kind: .css(.css), aliases: ["postcss", "pcss", "wxss", "tailwindcss"]),
        SyntaxLanguageEntry(id: "scss", name: "SCSS", kind: .css(.scss), aliases: []),
        SyntaxLanguageEntry(id: "sass", name: "Sass", kind: .css(.sass), aliases: []),
        SyntaxLanguageEntry(id: "less", name: "Less", kind: .css(.less), aliases: []),
        SyntaxLanguageEntry(id: "yaml", name: "YAML", kind: .yaml, aliases: ["yml", "eyaml", "eyml", "clang-format", "docker-compose", "compose", "k8s", "kubernetes", "kubectl", "helm", "ansible", "github-actions", "workflow", "openapi", "swagger", "cff", "gitlab-ci", "travis", "circleci", "azure-pipelines", "dependabot", "sls", "netplan", "pubspec", "mkdocs", "conda", "environment.yml"]),
        SyntaxLanguageEntry(id: "toml", name: "TOML", kind: .toml, aliases: ["cargo.toml", "pyproject", "pyproject.toml", "pipfile", "cargo.lock", "uv.lock", "poetry.lock", "netlify.toml"]),
        SyntaxLanguageEntry(id: "ini", name: "INI", kind: .ini(.ini), aliases: ["cfg", "conf", "config", "cnf", "dosini", "editorconfig", ".editorconfig", "gitconfig", ".gitconfig", "gitmodules", "desktop", "inf", "reg", "systemd", "service", "socket", "timer", "npmrc", ".npmrc", "pylintrc", "flake8", "tox", "setup.cfg", "hgrc", "my.cnf", "php.ini", "odbc", "mypy", "unit", "wireguard"]),
        SyntaxLanguageEntry(id: "properties", name: "Properties", kind: .ini(.properties), aliases: ["java-properties", "jproperties", "gradle.properties"]),
        SyntaxLanguageEntry(id: "dotenv", name: ".env", kind: .ini(.dotenv), aliases: ["env", ".env", "envrc", ".envrc", "env.local", ".env.local", "env.example", ".env.example"]),
        SyntaxLanguageEntry(id: "markdown", name: "Markdown", kind: .markdown, aliases: ["md", "mkd", "mdown", "mkdn", "mdwn", "mdx", "rmd", "rmarkdown", "gfm", "commonmark", "qmd", "quarto", "livemd", "readme", "readme.md"]),
        SyntaxLanguageEntry(id: "dockerfile", name: "Dockerfile", kind: .dockerfile, aliases: ["docker", "containerfile"]),
        SyntaxLanguageEntry(id: "makefile", name: "Makefile", kind: .makefile, aliases: ["make", "mk", "mak", "gnumakefile", "bsdmakefile", "mkfile"]),
        SyntaxLanguageEntry(id: "bash", name: "Bash", kind: .shell(.bash), aliases: ["sh", "shell", "shellscript", "shell-script", "ksh", "dash", "ash", "mksh", "busybox", "bashrc", ".bashrc", "bash_profile", ".bash_profile", "profile", "csh", "tcsh", "sh-script", "openrc", "ebuild", "eclass", "pkgbuild", "apkbuild", "shell_script", "posix"]),
        SyntaxLanguageEntry(id: "zsh", name: "Zsh", kind: .shell(.zsh), aliases: ["zshrc", ".zshrc", "zshenv", "zprofile", "zlogin", "oh-my-zsh"]),
        SyntaxLanguageEntry(id: "fish", name: "Fish", kind: .shell(.fish), aliases: ["fishshell"]),
        SyntaxLanguageEntry(id: "console", name: "Shell Session", kind: .console, aliases: ["shell-session", "shellsession", "sh-session", "bash-session", "zsh-session", "terminal", "term", "session", "shell-console", "bash-console", "prompt", "commandline", "command-line", "cli", "shell-command"]),
        SyntaxLanguageEntry(id: "powershell", name: "PowerShell", kind: .powershell, aliases: ["ps", "ps1", "psm1", "psd1", "pwsh", "posh", "ps1xml", "powershell-session"]),
        SyntaxLanguageEntry(id: "batch", name: "Batch", kind: .batch, aliases: ["bat", "cmd", "dos", "winbatch", "batchfile", "btm", "doscon"]),
        SyntaxLanguageEntry(id: "diff", name: "Diff", kind: .diff, aliases: ["patch", "udiff", "git-diff", "gitdiff", "rej"]),
        SyntaxLanguageEntry(id: "gitcommit", name: "Git Commit", kind: .gitCommit, aliases: ["git-commit", "commit", "commit_editmsg", "commit-msg", "commitmsg", "git-commit-msg"]),
        SyntaxLanguageEntry(id: "gitrebase", name: "Git Rebase", kind: .gitRebase, aliases: ["git-rebase", "git-rebase-todo", "rebase", "rebase-todo"]),
        SyntaxLanguageEntry(id: "regex", name: "Regex", kind: .regex, aliases: ["regexp", "re", "pcre", "regular-expression"]),
        SyntaxLanguageEntry(id: "http", name: "HTTP", kind: .http, aliases: ["https", "request", "rest", "restclient", "rest-client"]),
        SyntaxLanguageEntry(id: "latex", name: "LaTeX", kind: .latex, aliases: ["tex", "context", "sty", "cls", "katex", "mathjax", "math", "amsmath", "plaintex", "xetex", "lualatex", "pdflatex", "dtx", "ltx", "tikz"]),
        SyntaxLanguageEntry(id: "clojure", name: "Clojure", kind: .lisp(.clojure), aliases: ["clj", "cljs", "cljc", "cljx", "edn", "clojurescript", "bb", "babashka", "fennel", "fnl"]),
        SyntaxLanguageEntry(id: "lisp", name: "Common Lisp", kind: .lisp(.commonLisp), aliases: ["common-lisp", "commonlisp", "cl", "lsp", "asd", "sbcl"]),
        SyntaxLanguageEntry(id: "scheme", name: "Scheme", kind: .lisp(.scheme), aliases: ["scm", "ss", "sld", "sls", "guile", "chicken", "chez", "gerbil", "mit-scheme", "sicp"]),
        SyntaxLanguageEntry(id: "racket", name: "Racket", kind: .lisp(.racket), aliases: ["rkt", "rktl", "rktd"]),
        SyntaxLanguageEntry(id: "elisp", name: "Emacs Lisp", kind: .lisp(.elisp), aliases: ["emacs-lisp", "emacslisp", "el", "emacs"]),
        SyntaxLanguageEntry(id: "wat", name: "WebAssembly", kind: .lisp(.scheme), aliases: ["wast", "webassembly", "wasm-text"]),
        SyntaxLanguageEntry(id: "asm", name: "Assembly", kind: .asm, aliases: ["assembly", "nasm", "masm", "gas", "x86", "x86asm", "x86-64", "x86_64", "x64", "amd64", "arm", "armasm", "arm64", "aarch64", "s", "mips", "mipsasm", "riscv", "risc-v", "avr", "6502", "z80", "68k", "m68k", "tasm", "yasm", "fasm", "asm6502", "nasm-x86"]),
        SyntaxLanguageEntry(id: "nginx", name: "Nginx", kind: .nginx, aliases: ["nginxconf", "nginx.conf", "openresty"]),
        SyntaxLanguageEntry(id: "apache", name: "Apache", kind: .apache, aliases: ["apacheconf", "htaccess", ".htaccess", "httpd", "httpd.conf", "apache2"])
    ]

    static let byId: [String: SyntaxLanguageEntry] = {
        var map: [String: SyntaxLanguageEntry] = [:]
        for entry in entries { map[entry.id] = entry }
        return map
    }()

    /// Lower-cased alias (including every id) → canonical id.
    static let aliases: [String: String] = {
        var map: [String: String] = [:]
        for entry in entries {
            map[entry.id] = entry.id
            for alias in entry.aliases where map[alias] == nil { map[alias] = entry.id }
        }
        return map
    }()

    static func language(id: String) -> SyntaxLanguage? { byId[id]?.language }

    static func lexerKind(forId id: String) -> SyntaxLexerKind? {
        if let entry = byId[id] { return entry.kind }
        if let canonical = aliases[id.lowercased()] { return byId[canonical]?.kind }
        return nil
    }

    static func resolve(_ fenceInfo: String) -> SyntaxLanguage? {
        var info = fenceInfo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !info.isEmpty else { return nil }
        if info.hasPrefix("{") { info.removeFirst() }
        info = info.trimmingCharacters(in: .whitespaces)
        let stops: Set<Character> = [" ", "\t", "{", "}", ",", ";", "(", ")", "[", "]", "=", "\"", "'", "`", "|"]
        var word = String(info.prefix { !stops.contains($0) }).lowercased()
        while word.hasPrefix(".") && word.count > 1 { word.removeFirst() }
        for prefix in ["language-", "lang-", "source."] where word.hasPrefix(prefix) && word.count > prefix.count {
            word.removeFirst(prefix.count)
        }
        guard !word.isEmpty else { return nil }
        if let id = aliases[word] { return language(id: id) }
        // "python:main.py", "rust,ignore" style suffixes.
        if let colon = word.firstIndex(of: ":") {
            if let id = aliases[String(word[..<colon])] { return language(id: id) }
            let rest = String(word[word.index(after: colon)...])
            if !rest.isEmpty, let lang = fileLanguage(rest) { return lang }
        }
        if let lang = fileLanguage(word) { return lang }
        if word.hasPrefix("diff-") || word.hasSuffix("-diff") || word.hasSuffix(".diff") || word.hasSuffix(".patch") {
            return language(id: "diff")
        }
        if let plus = word.firstIndex(of: "+") {
            // "html+erb" → template flavour; "jinja+yaml" → first part.
            let tail = String(word[word.index(after: plus)...])
            let head = String(word[..<plus])
            if let id = aliases[tail], head == "html" || head == "htm" { return language(id: id) }
            if let id = aliases[head] { return language(id: id) }
        }
        let trimmed = String(word.reversed().drop { $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }.reversed())
        if trimmed != word, !trimmed.isEmpty, let id = aliases[trimmed] { return language(id: id) }
        return nil
    }

    /// Resolves file names and paths ("src/main.rs", "Dockerfile.dev", "CMakeLists.txt").
    static func fileLanguage(_ word: String) -> SyntaxLanguage? {
        let base = word.split(separator: "/").last.map(String.init) ?? word
        if let id = aliases[base] { return language(id: id) }
        if base.hasPrefix("dockerfile") || base.hasSuffix(".dockerfile") || base.hasPrefix("containerfile") { return language(id: "dockerfile") }
        if base.hasPrefix("makefile") || base == "gnumakefile" { return language(id: "makefile") }
        if base.hasPrefix(".env") { return language(id: "dotenv") }
        if base.hasPrefix("jenkinsfile") { return language(id: "groovy") }
        guard let dot = base.lastIndex(of: "."), dot != base.startIndex || base.count > 1 else { return nil }
        let ext = String(base[base.index(after: dot)...])
        guard !ext.isEmpty, base.contains(".") else { return nil }
        if let id = aliases[ext] { return language(id: id) }
        return nil
    }
}
