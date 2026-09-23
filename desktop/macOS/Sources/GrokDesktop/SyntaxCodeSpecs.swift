import Foundation

/// Language tables for the generic lexer. Each spec is built lazily on first use.
enum SyntaxSpecs {
    static func spec(_ id: String) -> SyntaxLangSpec? {
        switch id {
        case "swift": return swift
        case "python": return python
        case "javascript": return javascript
        case "typescript": return typescript
        case "rust": return rust
        case "go": return go
        case "c": return c
        case "cpp": return cpp
        case "objectivec": return objectiveC
        case "objectivecpp": return objectiveCpp
        case "csharp": return csharp
        case "java": return java
        case "kotlin": return kotlin
        case "scala": return scala
        case "groovy": return groovy
        case "dart": return dart
        case "ruby": return ruby
        case "php": return php
        case "perl": return perl
        case "lua": return lua
        case "r": return r
        case "julia": return julia
        case "haskell": return haskell
        case "elm": return elm
        case "ocaml": return ocaml
        case "fsharp": return fsharp
        case "elixir": return elixir
        case "erlang": return erlang
        case "zig": return zig
        case "nim": return nim
        case "solidity": return solidity
        case "graphql": return graphql
        case "protobuf": return protobuf
        case "hcl": return hcl
        case "nix": return nix
        case "sql": return sql
        case "matlab": return matlab
        case "fortran": return fortran
        case "vb": return visualBasic
        case "pascal": return pascal
        case "awk": return awk
        case "cmake": return cmake
        case "vim": return vim
        case "glsl": return glsl
        case "hlsl": return hlsl
        case "wgsl": return wgsl
        case "cuda": return cuda
        case "prisma": return prisma
        case "mermaid": return mermaid
        case "dot": return dot
        case "gitignore": return gitignore
        case "jinja": return jinjaExpression
        default: return nil
        }
    }

    // MARK: - Apple

    static let swift: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.cComments(nested: true)
        s.keywords("""
            associatedtype deinit fileprivate import init inout internal let open operator private precedencegroup \
            public rethrows static subscript var break case catch continue default defer do else fallthrough for \
            guard if in repeat return throw switch where while as is try await async throws Any some any \
            nonisolated isolated consuming borrowing mutating nonmutating override final required convenience lazy \
            weak unowned optional dynamic indirect prefix postfix infix get set willSet didSet package sending \
            consume copy discard each macro
            """)
        s.valueKeywords("self Self super")
        s.functionDefiners("func")
        s.typeDefiners("class struct enum protocol extension typealias actor")
        s.constants("true false nil")
        s.allowedAfterDot("self Self init Type Protocol")
        s.contextual("get set willSet didSet some any lazy weak unowned optional dynamic indirect prefix postfix infix convenience required override final open package mutating nonmutating isolated nonisolated consuming borrowing sending consume copy discard each macro actor async")
        s.tripleDouble = true
        s.singleQuote = .none
        s.backtick = .identifier
        s.interpolation = .swift
        s.at = .attribute
        s.dollar = .swift
        s.swiftPound = true
        s.regex = .js
        s.capitalizedCallIsType = true
        s.allCapsConstants = false
        return s
    }()

    static let objectiveC: SyntaxLangSpec = {
        var s = c
        s.words.add("""
            @interface @implementation @end @property @synthesize @dynamic @protocol @optional @required @class \
            @selector @encode @try @catch @finally @throw @autoreleasepool @synchronized @import @public @private \
            @protected @package @available @compatibility_alias @defs
            """, .keyword)
        s.keywords("""
            id instancetype nonatomic atomic strong weak assign copy retain readonly readwrite nullable nonnull \
            _Nullable _Nonnull __block __weak __strong __unsafe_unretained in out inout oneway bycopy byref \
            IBOutlet IBAction IBInspectable IB_DESIGNABLE NS_ASSUME_NONNULL_BEGIN NS_ASSUME_NONNULL_END
            """)
        s.valueKeywords("self super")
        s.types("BOOL SEL IMP Class NSInteger NSUInteger CGFloat")
        s.constants("YES NO nil Nil NULL")
        s.at = .objc
        s.objcSelectors = true
        return s
    }()

    static let objectiveCpp: SyntaxLangSpec = {
        var s = cpp
        s.words.add("""
            @interface @implementation @end @property @synthesize @dynamic @protocol @optional @required @class \
            @selector @encode @try @catch @finally @throw @autoreleasepool @synchronized @import @public @private \
            @protected @package @available
            """, .keyword)
        s.keywords("id instancetype nonatomic atomic strong weak assign copy retain readonly readwrite nullable nonnull __block __weak __strong IBOutlet IBAction")
        s.valueKeywords("self super")
        s.types("BOOL SEL IMP Class NSInteger NSUInteger CGFloat")
        s.constants("YES NO nil Nil")
        s.at = .objc
        s.objcSelectors = true
        return s
    }()

    // MARK: - Python & friends

    static let python: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("#")
        s.keywords("""
            and as assert async await break continue del elif else except finally for from global if import in is \
            lambda nonlocal not or pass raise return try while with yield
            """)
        s.valueKeywords("self cls")
        s.softKeywords("match case type")
        s.functionDefiners("def")
        s.typeDefiners("class")
        s.constants("True False None NotImplemented Ellipsis __debug__")
        s.types("int float str bool bytes bytearray list dict set frozenset tuple object complex memoryview")
        s.builtins("""
            print len range open input enumerate zip map filter sorted reversed sum min max abs any all isinstance \
            issubclass hasattr getattr setattr delattr iter next repr hash id super property staticmethod \
            classmethod format round divmod pow chr ord hex oct bin callable vars dir globals locals exec eval \
            compile breakpoint help ascii __import__ aiter anext
            """)
        s.tripleDouble = true
        s.tripleSingle = true
        s.prefixes = .python
        s.at = .decorator
        s.capitalizedCallIsType = true
        return s
    }()

    static let jinjaExpression: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.keywords("""
            if elif else endif for endfor in not and or is block endblock extends include import from macro endmacro \
            set endset with endwith raw endraw filter endfilter call endcall autoescape endautoescape load url \
            csrf_token static trans blocktrans endblocktrans comment endcomment unless endunless case when capture \
            endcapture assign each endeach as empty cycle firstof now spaceless endspaceless verbatim endverbatim \
            else if unless tablerow endtablerow increment decrement render break continue
            """)
        s.constants("true false none True False None null nil")
        s.capitalized = nil
        s.allCapsConstants = false
        return s
    }()

    // MARK: - JavaScript family

    static let javascript: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.cComments()
        s.keywords("""
            break case catch const continue debugger default delete do else export extends finally for if import in \
            instanceof let new return switch throw try typeof var void while with yield async await of static get \
            set from as target meta
            """)
        s.valueKeywords("this super arguments")
        s.functionDefiners("function")
        s.typeDefiners("class")
        s.constants("true false null undefined NaN Infinity")
        s.contextual("get set of from as async static target meta")
        s.backtick = .template
        s.regex = .js
        s.jsx = true
        s.at = .attribute
        s.hashPrivate = true
        s.identDollar = true
        s.capitalizedCallIsType = true
        return s
    }()

    static let typescript: SyntaxLangSpec = {
        var s = javascript
        s.keywords("""
            implements namespace module declare abstract private protected public readonly keyof infer is asserts \
            satisfies override unique accessor out enum
            """)
        s.typeDefiners("interface type enum class namespace")
        s.types("string number boolean any unknown never void object symbol bigint")
        s.contextual("type declare namespace module is asserts infer keyof readonly abstract override accessor out satisfies")
        return s
    }()

    // MARK: - Systems

    static let rust: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.cComments(nested: true)
        s.keywords("""
            as async await break const continue crate dyn else extern for if impl in let loop match mod move mut \
            pub ref return static super unsafe use where while yield macro_rules union try gen
            """)
        s.valueKeywords("self Self")
        s.functionDefiners("fn")
        s.typeDefiners("struct enum trait type")
        s.types("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str")
        s.constants("true false")
        s.allowedAfterDot("await")
        s.singleQuote = .rust
        s.multilineStrings = true
        s.prefixes = .rust
        s.rustAttributes = true
        s.macroBang = true
        s.capitalizedCallIsType = true
        return s
    }()

    static let go: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.cComments()
        s.keywords("""
            break case chan const continue default defer else fallthrough for go goto if import interface map \
            package range return select struct switch var
            """)
        s.functionDefiners("func")
        s.typeDefiners("type")
        s.types("""
            bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 \
            uint16 uint32 uint64 uintptr any comparable
            """)
        s.constants("true false nil iota")
        s.builtins("append cap clear close complex copy delete imag len make max min new panic print println real recover")
        s.singleQuote = .char
        s.backtick = .raw
        s.allCapsConstants = false
        s.capitalizedMembersPlain = true
        return s
    }()

    static let c: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.cComments()
        s.keywords("""
            auto break case const continue default do else extern for goto if inline register restrict return \
            sizeof static switch typedef volatile while _Alignas _Alignof _Atomic _Generic _Noreturn \
            _Static_assert _Thread_local alignas alignof static_assert thread_local typeof constexpr __attribute__ \
            __declspec __inline __restrict
            """)
        s.typeDefiners("struct enum union")
        s.types("""
            char double float int long short signed unsigned void bool _Bool _Complex size_t ssize_t ptrdiff_t \
            intptr_t uintptr_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t wchar_t off_t \
            pid_t va_list FILE time_t clock_t
            """)
        s.constants("NULL true false nullptr EOF stdin stdout stderr")
        s.singleQuote = .char
        s.prefixes = .cpp
        s.preprocessor = true
        s.arrowMemberAccess = true
        return s
    }()

    static let cpp: SyntaxLangSpec = {
        var s = c
        s.keywords("""
            and and_eq asm bitand bitor catch compl concept consteval constexpr constinit const_cast co_await \
            co_return co_yield decltype delete dynamic_cast explicit export friend mutable new noexcept not not_eq \
            operator or or_eq private protected public reinterpret_cast requires static_cast template throw try \
            typeid typename using virtual xor xor_eq override final import module
            """)
        s.valueKeywords("this")
        s.typeDefiners("class struct enum union namespace concept")
        s.types("""
            char8_t char16_t char32_t string wstring string_view vector unordered_map unordered_set unique_ptr \
            shared_ptr weak_ptr optional variant size_t nullptr_t map set pair tuple array deque
            """)
        s.cppDigitSeparators = true
        return s
    }()

    static let csharp: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.cComments()
        s.keywords("""
            abstract as break case catch checked const continue default delegate do else event explicit extern \
            finally fixed for foreach goto if implicit in internal is lock new operator out override params \
            private protected public readonly ref return sealed sizeof stackalloc static switch throw try typeof \
            unchecked unsafe using virtual volatile while add alias async await by descending dynamic equals from \
            get global group into join let nameof on orderby partial remove select set unmanaged var when \
            where yield init required file scoped with not and or managed notnull record
            """)
        s.valueKeywords("this base")
        s.typeDefiners("class struct interface enum record namespace")
        s.types("bool byte char decimal double float int long object sbyte short string uint ulong ushort void nint nuint")
        s.constants("true false null")
        s.contextual("add alias async await by descending dynamic equals from get global group into join let on orderby partial remove select set unmanaged var when where yield init required file scoped with managed notnull record")
        s.singleQuote = .char
        s.preprocessor = true
        s.csharpAttributes = true
        s.at = .csharp
        s.dollar = .csharp
        s.tripleDouble = true
        s.allCapsConstants = false
        s.capitalizedMembersPlain = true
        return s
    }()

    // MARK: - JVM

    static let java: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.cComments()
        s.keywords("""
            abstract assert break case catch continue default do else extends final finally for if implements \
            import instanceof native new package private protected public return static strictfp switch \
            synchronized throw throws transient try volatile while var sealed permits non-sealed yield goto const
            """)
        s.valueKeywords("this super")
        s.typeDefiners("class interface enum record")
        s.types("boolean byte char short int long float double void")
        s.constants("true false null")
        s.contextual("var sealed permits non-sealed yield record")
        s.singleQuote = .char
        s.tripleDouble = true
        s.at = .attribute
        s.identDollar = true
        s.capitalizedCallIsType = true
        return s
    }()

    static let kotlin: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.cComments(nested: true)
        s.keywords("""
            as break continue do else for if in is return throw try typeof val var when while by catch constructor \
            finally get import init set where actual abstract annotation companion const crossinline data enum expect external final infix inline inner \
            internal lateinit noinline open operator out override private protected public reified sealed suspend \
            tailrec vararg package
            """)
        s.valueKeywords("this super it")
        s.functionDefiners("fun")
        s.typeDefiners("class interface object typealias")
        s.constants("true false null")
        s.contextual("by get init set where actual abstract annotation companion const crossinline data enum expect external final infix inline inner internal lateinit noinline open operator out override private protected public reified sealed suspend tailrec vararg it")
        s.singleQuote = .char
        s.tripleDouble = true
        s.interpolation = .dollarBraceIdent
        s.at = .attribute
        s.backtick = .identifier
        s.capitalizedCallIsType = true
        return s
    }()

    static let scala: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.cComments(nested: true)
        s.keywords("""
            abstract case catch do else extends final finally for forSome if implicit import lazy match new \
            override package private protected return sealed throw try val var while with yield given using \
            export then end extension inline opaque transparent derives as
            """)
        s.valueKeywords("this super")
        s.functionDefiners("def")
        s.typeDefiners("class object trait type enum")
        s.constants("true false null")
        s.singleQuote = .char
        s.tripleDouble = true
        s.prefixes = .scala
        s.at = .attribute
        s.backtick = .identifier
        s.capitalizedCallIsType = true
        return s
    }()

    static let groovy: SyntaxLangSpec = {
        var s = java
        s.keywords("def in as trait")
        s.typeDefiners("class interface enum trait")
        s.singleQuote = .string
        s.tripleSingle = true
        s.interpolation = .dollarBraceIdent
        s.capitalizedCallIsType = false
        return s
    }()

    static let dart: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.cComments(nested: true)
        s.keywords("""
            abstract as assert async await base break case catch const continue covariant default deferred do \
            dynamic else export extends external factory final finally for get hide if implements import in \
            interface is late library new on operator part required rethrow return sealed set show static switch \
            sync throw try var when while with yield
            """)
        s.valueKeywords("this super")
        s.typeDefiners("class enum mixin extension typedef")
        s.types("int double num bool void dynamic Function")
        s.constants("true false null")
        s.tripleDouble = true
        s.tripleSingle = true
        s.prefixes = .dart
        s.interpolation = .dollarBraceIdent
        s.singleQuoteInterpolates = true
        s.at = .attribute
        s.capitalizedCallIsType = true
        s.allCapsConstants = false
        return s
    }()

    // MARK: - Scripting

    static let ruby: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("#")
        s.lineStartBlocks = [SyntaxDelimiterPair("=begin", "=end")]
        s.endMarkers = [Array("__END__".utf16)]
        s.keywords("""
            BEGIN END alias and begin break case defined? do else elsif end ensure for if in next not or redo rescue \
            retry return then undef unless until when while yield __method__ __FILE__ __LINE__ __ENCODING__ \
            include extend prepend attr_accessor attr_reader attr_writer private protected public module_function \
            raise loop lambda proc require require_relative
            """)
        s.valueKeywords("self super")
        s.functionDefiners("def")
        s.typeDefiners("class module")
        s.constants("true false nil")
        s.builtins("puts print p pp format sprintf printf gets rand sleep")
        s.singleQuote = .limited
        s.multilineStrings = true
        s.interpolation = .hashBrace
        s.backtick = .command
        s.at = .variable
        s.dollar = .variable
        s.symbols = true
        s.labelSymbols = true
        s.heredoc = .ruby
        s.percentLiterals = true
        s.regex = .ruby
        s.identQuestion = true
        s.identBang = true
        return s
    }()

    static let php: SyntaxLangSpec = {
        var s = SyntaxLangSpec(caseInsensitive: true)
        s.cComments()
        s.lineComment("#")
        s.keywords("""
            abstract and array as break callable case catch clone const continue declare default do echo else \
            elseif empty enddeclare endfor endforeach endif endswitch endwhile eval exit extends final finally fn \
            for foreach global goto if implements include include_once instanceof insteadof isset list match \
            namespace new or print private protected public readonly require require_once return static switch \
            throw try unset use var while xor yield from die
            """)
        s.valueKeywords("self parent")
        s.functionDefiners("function")
        s.typeDefiners("class interface trait enum")
        s.types("int float bool string void mixed never object iterable")
        s.constants("true false null __CLASS__ __DIR__ __FILE__ __FUNCTION__ __LINE__ __METHOD__ __NAMESPACE__ __TRAIT__")
        s.singleQuote = .limited
        s.multilineStrings = true
        s.interpolation = .php
        s.backtick = .command
        s.dollar = .variable
        s.phpAttributes = true
        s.heredoc = .php
        s.arrowMemberAccess = true
        s.capitalizedCallIsType = true
        return s
    }()

    static let perl: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("#")
        s.lineStartBlocks = [SyntaxDelimiterPair("=", "=cut")]
        s.endMarkers = [Array("__END__".utf16), Array("__DATA__".utf16)]
        s.keywords("""
            my our local state sub package use require no if elsif else unless while until for foreach last next \
            redo return do eval and or not xor eq ne lt gt le ge cmp defined undef BEGIN END given when default
            """)
        s.functionDefiners("sub")
        s.typeDefiners("package")
        s.builtins("""
            print say printf sprintf die warn chomp chop split join keys values each exists delete push pop shift \
            unshift map grep sort reverse open close bless ref scalar length substr index lc uc lcfirst ucfirst \
            exit wantarray local sprintf abs int sqrt time localtime
            """)
        s.singleQuote = .limited
        s.multilineStrings = true
        s.interpolation = .perl
        s.backtick = .command
        s.at = .variable
        s.dollar = .perl
        s.heredoc = .perl
        s.regex = .ruby
        s.perlQuoteOperators = true
        s.arrowMemberAccess = true
        s.capitalized = nil
        return s
    }()

    static let lua: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("--")
        s.keywords("and break do else elseif end for goto if in local not or repeat return then until while")
        s.valueKeywords("self")
        s.functionDefiners("function")
        s.constants("true false nil")
        s.builtins("""
            print pairs ipairs require tostring tonumber setmetatable getmetatable assert error pcall xpcall select \
            next rawget rawset rawequal unpack type collectgarbage dofile loadstring load
            """)
        s.luaLongBrackets = true
        s.capitalized = nil
        return s
    }()

    static let r: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("#")
        s.keywords("if else repeat while function for in next break return switch")
        s.constants("TRUE FALSE NULL NA NA_integer_ NA_real_ NA_character_ NA_complex_ Inf NaN T F")
        s.builtins("library require c list print cat paste paste0 length sum mean")
        s.backtick = .identifier
        s.identDot = true
        s.percentOperators = true
        s.multilineStrings = true
        s.capitalized = nil
        s.allCapsConstants = false
        return s
    }()

    static let julia: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("#")
        s.blockComment("#=", "=#")
        s.nestedComments = true
        s.keywords("""
            abstract baremodule begin break catch const continue do else elseif end export finally for global if \
            import in isa let local module mutable primitive quote return try using where while outer
            """)
        s.functionDefiners("function macro")
        s.typeDefiners("struct type")
        s.constants("true false nothing missing Inf NaN pi im")
        s.tripleDouble = true
        s.singleQuote = .transpose
        s.interpolation = .julia
        s.prefixes = .julia
        s.at = .attribute
        s.symbols = true
        s.identBang = true
        s.backtick = .command
        s.multilineStrings = true
        return s
    }()

    // MARK: - Functional

    static let haskell: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("--")
        s.blockComment("{-", "-}")
        s.nestedComments = true
        s.keywords("""
            case class data default deriving do else family forall foreign hiding if import in infix infixl infixr \
            instance let mdo module newtype of proc qualified rec then type where as pattern
            """)
        s.constants("True False Nothing otherwise")
        s.singleQuote = .ml
        s.haskellDashes = true
        s.haskellPragma = true
        s.identPrime = true
        s.callHeuristic = false
        s.signatureFunctions = true
        s.backtick = .identifier
        s.allCapsConstants = false
        return s
    }()

    static let elm: SyntaxLangSpec = {
        var s = haskell
        s.keywords("module exposing import as type alias port if then else case of let in effect where")
        s.signatureSingleColon = true
        return s
    }()

    static let ocaml: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.blockComment("(*", "*)")
        s.nestedComments = true
        s.keywords("""
            and as assert begin class constraint do done downto else end exception external for fun function \
            functor if in include inherit initializer lazy let match method module mutable new nonrec object of \
            open or private rec sig struct then to try type val virtual when while with land lor lxor lsl lsr asr mod
            """)
        s.constants("true false")
        s.types("int float bool char string unit list array option ref exn bytes int32 int64 nativeint")
        s.singleQuote = .ml
        s.identPrime = true
        s.multilineStrings = true
        s.allCapsConstants = false
        return s
    }()

    static let fsharp: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("//")
        s.blockComment("(*", "*)")
        s.nestedComments = true
        s.keywords("""
            abstract and as assert base begin class default delegate do done downcast downto elif else end exception \
            extern finally fixed for fun function global if in inherit inline interface internal lazy let match \
            member module mutable namespace new not of open or override private public rec return select sig \
            static struct then to try type upcast use val void when while with yield async task seq query
            """)
        s.valueKeywords("this")
        s.constants("true false null")
        s.types("int float bool char string unit list array option byte sbyte int16 uint16 int64 uint64 decimal obj")
        s.singleQuote = .ml
        s.tripleDouble = true
        s.identPrime = true
        s.fsharpAttributes = true
        s.dollar = .csharp
        s.at = .csharp
        s.multilineStrings = true
        s.allCapsConstants = false
        return s
    }()

    static let elixir: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("#")
        s.keywords("""
            after and catch cond do else end fn for if import in not or quote raise receive require rescue try \
            unless unquote use when with alias defstruct defexception defoverridable __MODULE__ __DIR__ __ENV__ \
            __CALLER__ __STACKTRACE__
            """)
        s.functionDefiners("def defp defmacro defmacrop defguard defguardp defdelegate")
        s.typeDefiners("defmodule defprotocol defimpl")
        s.constants("true false nil")
        s.tripleDouble = true
        s.multilineStrings = true
        s.singleQuoteInterpolates = true
        s.interpolation = .hashBrace
        s.at = .attribute
        s.symbols = true
        s.labelSymbols = true
        s.sigils = true
        s.question = .elixirChar
        s.identQuestion = true
        s.identBang = true
        s.allCapsConstants = false
        return s
    }()

    static let erlang: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("%")
        s.keywords("""
            after and andalso band begin bnot bor bsl bsr bxor case catch cond div end fun if let not of or orelse \
            receive rem try when xor maybe else
            """)
        s.constants("true false undefined ok error")
        s.capitalized = .variable
        s.allCapsConstants = false
        s.erlangAttributes = true
        s.question = .erlangMacro
        s.erlangBase = true
        s.singleQuote = .char
        s.multilineStrings = true
        return s
    }()

    // MARK: - Modern systems

    static let zig: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("//")
        s.keywords("""
            addrspace align allowzero and anyframe anytype asm async await break callconv catch comptime const \
            continue defer else enum errdefer error export extern for if inline linksection noalias noinline \
            nosuspend opaque or orelse packed pub resume return linksection struct suspend switch test threadlocal \
            try union unreachable usingnamespace var volatile while
            """)
        s.functionDefiners("fn")
        s.types("""
            i8 u8 i16 u16 i32 u32 i64 u64 i128 u128 isize usize c_int c_uint c_long c_ulong c_char c_short \
            c_longlong f16 f32 f64 f80 f128 bool void noreturn type anyerror comptime_int comptime_float anyopaque
            """)
        s.constants("true false null undefined")
        s.singleQuote = .char
        s.at = .zig
        s.zigLineStrings = true
        s.capitalizedCallIsType = true
        return s
    }()

    static let nim: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("#")
        s.blockComment("#[", "]#")
        s.nestedComments = true
        s.keywords("""
            addr and as asm bind block break case cast concept const continue converter defer discard distinct div \
            do elif else end enum except export finally for from if import in include interface is isnot let \
            mixin mod not notin object of or out ptr raise ref return shl shr static try tuple using var when \
            while xor yield
            """)
        s.functionDefiners("proc func method iterator template macro converter")
        s.types("""
            int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float float32 float64 bool char string \
            cstring pointer seq array set openArray varargs void auto untyped typed Natural Positive
            """)
        s.valueKeywords("result")
        s.constants("true false nil")
        s.tripleDouble = true
        s.singleQuote = .char
        s.prefixes = .nim
        s.nimPragma = true
        s.backtick = .identifier
        s.allCapsConstants = false
        return s
    }()

    static let solidity: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.cComments()
        s.keywords("""
            pragma solidity import is return returns if else for while do break continue new delete public \
            private internal external view pure payable constant immutable virtual override memory storage \
            calldata using try catch assembly unchecked emit anonymous indexed type revert require assert \
            constructor fallback receive
            """)
        s.valueKeywords("this super")
        s.functionDefiners("function modifier event error")
        s.typeDefiners("contract interface library struct enum abstract")
        var sized = ["address", "bool", "string", "bytes", "int", "uint", "fixed", "ufixed", "mapping"]
        for bits in stride(from: 8, through: 256, by: 8) { sized += ["int\(bits)", "uint\(bits)"] }
        for n in 1...32 { sized.append("bytes\(n)") }
        s.types(sized.joined(separator: " "))
        s.constants("true false wei gwei ether seconds minutes hours days weeks")
        s.variables("msg block tx abi")
        return s
    }()

    // MARK: - Schemas & config

    static let graphql: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("#")
        s.keywords("query mutation subscription fragment on implements directive repeatable schema extend")
        s.typeDefiners("type interface union enum input scalar")
        s.constants("true false null")
        s.tripleDouble = true
        s.singleQuote = .none
        s.dollar = .variable
        s.at = .attribute
        s.allCapsConstants = true
        return s
    }()

    static let protobuf: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.cComments()
        s.keywords("syntax edition package import option oneof map repeated optional required reserved extensions extend stream to max weak public group returns")
        s.typeDefiners("message enum service")
        s.functionDefiners("rpc")
        s.types("double float int32 int64 uint32 uint64 sint32 sint64 fixed32 fixed64 sfixed32 sfixed64 bool string bytes")
        s.constants("true false")
        return s
    }()

    static let hcl: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("#", "//")
        s.blockComment("/*", "*/")
        s.keywords("""
            resource data variable output module provider locals terraform backend required_providers moved \
            import check removed for in if else endif endfor dynamic content lifecycle
            """)
        s.variables("var local each self")
        s.constants("true false null")
        s.interpolation = .dollarBrace
        s.singleQuote = .none
        s.heredoc = .hcl
        s.assignmentKeys = true
        s.capitalized = nil
        s.allCapsConstants = false
        return s
    }()

    static let nix: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("#")
        s.blockComment("/*", "*/")
        s.keywords("let in with rec inherit if then else assert or")
        s.constants("true false null")
        s.builtins("builtins import map toString derivation fetchurl fetchTarball fetchGit abort throw baseNameOf dirOf isNull removeAttrs mkDerivation")
        s.interpolation = .dollarBrace
        s.multilineStrings = true
        s.singleQuote = .nixIndented
        s.identDash = true
        s.identPrime = true
        s.assignmentKeys = true
        s.nixPaths = true
        s.capitalized = nil
        return s
    }()

    static let sql: SyntaxLangSpec = {
        var s = SyntaxLangSpec(caseInsensitive: true)
        s.lineComment("--")
        s.blockComment("/*", "*/")
        s.keywords("""
            select from where and or not in is like ilike between exists as on join inner left right full outer \
            cross natural using group by order having limit offset fetch first next rows row only union all \
            distinct intersect except insert into values update set delete create table view index unique primary \
            key foreign references constraint default check alter add drop column rename to truncate if case when \
            then else end with recursive returning asc desc nulls begin commit rollback transaction savepoint grant \
            revoke cascade restrict trigger function procedure returns return language declare execute exec over \
            partition window range preceding following unbounded current lateral schema database temporary temp \
            replace materialized explain analyze vacuum auto_increment autoincrement identity generated always \
            stored virtual collate escape some any filter within merge matched use show describe top pivot unpivot \
            loop while for do raise notice exception perform out inout variadic security definer invoker immutable \
            stable volatile strict called setof type extension sequence owned owner policy enable disable lock \
            share mode nowait skip locked conflict nothing each statement before after instead of go print \
            elsif elseif open close cursor deallocate prepare call handler continue exit leave iterate repeat until \
            interval zone at local session global option comment copy cluster reindex listen notify returning
            """)
        s.types("""
            int integer bigint smallint tinyint mediumint serial bigserial smallserial decimal numeric real float \
            double precision varchar char character text tinytext mediumtext longtext blob bytea boolean bool date \
            time timestamp timestamptz datetime datetime2 smalldatetime uuid json jsonb money bit varbinary binary \
            nvarchar nchar ntext xml array enum geometry geography inet cidr macaddr tsvector int2 int4 int8 float4 \
            float8 varying unsigned signed
            """)
        s.constants("true false null unknown")
        s.builtins("""
            count sum avg min max coalesce nullif cast convert now current_date current_time current_timestamp lower \
            upper length substring trim round abs concat date_trunc extract row_number rank dense_rank lag lead \
            string_agg array_agg json_agg jsonb_agg greatest least ifnull isnull
            """)
        s.singleQuote = .string
        s.escapes = false
        s.doubledQuotes = true
        s.multilineStrings = true
        s.backtick = .identifier
        s.prefixes = .sql
        s.dollar = .variable
        s.at = .variable
        s.capitalized = nil
        s.allCapsConstants = false
        return s
    }()

    // MARK: - Scientific & legacy

    static let matlab: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("%", "#", "...")
        s.lineStartBlocks = [SyntaxDelimiterPair("%{", "%}")]
        s.keywords("""
            break case catch classdef continue else elseif end for global if otherwise parfor persistent return \
            spmd switch try while properties methods events enumeration arguments
            """)
        s.functionDefiners("function")
        s.constants("true false pi eps Inf NaN NA inf nan")
        s.singleQuote = .transpose
        s.escapes = false
        s.doubledQuotes = true
        s.capitalized = nil
        s.allCapsConstants = false
        return s
    }()

    static let fortran: SyntaxLangSpec = {
        var s = SyntaxLangSpec(caseInsensitive: true)
        s.lineComment("!")
        s.keywords("""
            program end subroutine module use implicit none contains call return if then else elseif endif do \
            enddo while exit cycle select case default where elsewhere forall interface class allocate deallocate \
            allocatable intent in out inout parameter dimension pointer target save data common equivalence \
            external intrinsic optional public private recursive pure elemental result stop print write read open \
            close format go to goto include block associate procedure abstract extends only kind len sequence \
            namelist entry nullify import endfunction endsubroutine endmodule endprogram endtype endinterface \
            continue concurrent
            """)
        s.functionDefiners("function subroutine")
        s.typeDefiners("type")
        s.types("integer real double precision complex character logical")
        s.words.add(".true. .false.", .constant)
        s.words.add(".and. .or. .not. .eqv. .neqv. .eq. .ne. .lt. .le. .gt. .ge.", .keyword)
        s.singleQuote = .string
        s.escapes = false
        s.doubledQuotes = true
        s.fortranDots = true
        s.fortranExponent = true
        s.capitalized = nil
        s.allCapsConstants = false
        return s
    }()

    static let visualBasic: SyntaxLangSpec = {
        var s = SyntaxLangSpec(caseInsensitive: true)
        s.lineComment("'")
        s.lineStartComments = [Array("REM ".utf16), Array("rem ".utf16), Array("Rem ".utf16)]
        s.keywords("""
            AddHandler AddressOf Alias And AndAlso As ByRef ByVal Call Case Catch Const Continue Declare Default \
            Delegate Dim DirectCast Do Each Else ElseIf End EndIf Erase Error Event Exit Finally For Friend Get \
            GetType Global GoTo Handles If Implements Imports In Inherits Is IsNot Let Lib Like Loop Me Mod \
            MustInherit MustOverride MyBase MyClass Namespace Narrowing New Next Not Of On Operator Option Optional \
            Or OrElse Overloads Overridable Overrides ParamArray Partial Private Property Protected Public \
            RaiseEvent ReadOnly ReDim RemoveHandler Resume Return Select Set Shadows Shared Static Step Stop \
            SyncLock Then Throw To Try TryCast TypeOf Using When While Widening With WithEvents WriteOnly Xor Async \
            Await Yield Iterator Wend
            """)
        s.functionDefiners("Sub Function")
        s.typeDefiners("Class Module Structure Interface Enum")
        s.types("Boolean Byte Char Date Decimal Double Integer Long Object SByte Short Single String UInteger ULong UShort Variant")
        s.constants("True False Nothing")
        s.singleQuote = .none
        s.escapes = false
        s.doubledQuotes = true
        s.preprocessor = true
        s.capitalized = nil
        s.allCapsConstants = false
        return s
    }()

    static let pascal: SyntaxLangSpec = {
        var s = SyntaxLangSpec(caseInsensitive: true)
        s.lineComment("//")
        s.blockComment("{", "}")
        s.blockComment("(*", "*)")
        s.keywords("""
            and array as begin case class const constructor destructor div do downto else end except exports file \
            finalization finally for goto if implementation in inherited initialization inline interface is label \
            library mod nil not object of or out packed program property raise record repeat resourcestring set \
            shl shr then threadvar to try type unit until uses var while with xor private protected public \
            published override virtual abstract overload strict
            """)
        s.functionDefiners("function procedure")
        s.types("integer real boolean char byte word longint cardinal double single extended string ansistring int64")
        s.constants("true false nil")
        s.doubleQuote = false
        s.escapes = false
        s.doubledQuotes = true
        s.capitalized = nil
        s.allCapsConstants = false
        return s
    }()

    static let awk: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("#")
        s.keywords("BEGIN END BEGINFILE ENDFILE if else while for do break continue next nextfile exit return delete in getline")
        s.functionDefiners("function func")
        s.builtins("""
            print printf length substr index split sub gsub gensub match sprintf tolower toupper system close \
            srand rand int sin cos atan2 exp log sqrt strftime systime fflush
            """)
        s.constants("NR NF FS OFS RS ORS FILENAME FNR RSTART RLENGTH SUBSEP ENVIRON ARGC ARGV CONVFMT OFMT")
        s.singleQuote = .none
        s.dollar = .awk
        s.regex = .js
        s.capitalized = nil
        return s
    }()

    static let cmake: SyntaxLangSpec = {
        var s = SyntaxLangSpec(caseInsensitive: true)
        s.blockComment("#[[", "]]")
        s.lineComment("#")
        s.keywords("""
            if elseif else endif foreach endforeach while endwhile function endfunction macro endmacro return break \
            continue block endblock
            """)
        s.constants("ON OFF TRUE FALSE YES NO")
        s.singleQuote = .none
        s.multilineStrings = true
        s.interpolation = .dollarBraceVariable
        s.dollar = .cmake
        s.identDash = false
        s.capitalized = nil
        return s
    }()

    static let vim: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineStartComments = [[34]]
        s.keywords("""
            function endfunction endf func endfunc let unlet const if elseif else endif for endfor in \
            while endwhile try catch finally endtry return call execute exe echo echom echomsg echoerr set setlocal \
            setglobal map nmap vmap xmap imap omap cmap noremap nnoremap vnoremap xnoremap inoremap onoremap \
            cnoremap tnoremap unmap autocmd au augroup command syntax highlight hi source runtime silent normal \
            abort range dict closure def enddef var export import vim9script filetype plugin indent on off \
            colorscheme packadd lua
            """)
        s.constants("v:true v:false v:null")
        s.escapes = true
        s.singleQuote = .string
        s.vimScopes = true
        s.capitalized = nil
        s.allCapsConstants = false
        return s
    }()

    // MARK: - Shaders & GPU

    static let glsl: SyntaxLangSpec = {
        var s = c
        s.keywords("""
            uniform attribute varying in out inout layout precision highp mediump lowp flat smooth noperspective \
            centroid discard buffer shared coherent readonly writeonly invariant subroutine
            """)
        s.types("""
            vec2 vec3 vec4 ivec2 ivec3 ivec4 uvec2 uvec3 uvec4 bvec2 bvec3 bvec4 dvec2 dvec3 dvec4 mat2 mat3 mat4 \
            mat2x2 mat3x3 mat4x4 sampler1D sampler2D sampler3D samplerCube sampler2DShadow image2D uint
            """)
        s.builtins("""
            texture texture2D normalize dot cross mix clamp smoothstep step length distance reflect refract pow \
            sin cos tan abs floor ceil fract mod min max sqrt exp log
            """)
        return s
    }()

    static let hlsl: SyntaxLangSpec = {
        var s = c
        s.keywords("cbuffer tbuffer register packoffset in out inout uniform static groupshared numthreads")
        s.types("""
            float2 float3 float4 float2x2 float3x3 float4x4 half half2 half3 half4 int2 int3 int4 uint uint2 uint3 \
            uint4 bool2 bool3 bool4 matrix vector Texture2D Texture3D TextureCube SamplerState RWTexture2D \
            StructuredBuffer RWStructuredBuffer
            """)
        s.builtins("mul saturate lerp normalize dot cross clamp smoothstep length pow frac")
        return s
    }()

    static let wgsl: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.cComments()
        s.keywords("let var const override struct return if else loop for while break continue switch case default discard continuing alias enable requires diagnostic")
        s.functionDefiners("fn")
        s.types("""
            f32 f16 i32 u32 bool vec2 vec3 vec4 vec2f vec3f vec4f vec2i vec3i vec4i vec2u vec3u vec4u mat2x2 mat3x3 \
            mat4x4 mat4x4f mat3x3f array ptr atomic sampler sampler_comparison texture_2d texture_3d texture_cube \
            texture_storage_2d texture_depth_2d uniform storage function private workgroup read write read_write
            """)
        s.constants("true false")
        s.at = .attribute
        s.singleQuote = .none
        return s
    }()

    static let cuda: SyntaxLangSpec = {
        var s = cpp
        s.keywords("__global__ __device__ __host__ __shared__ __constant__ __managed__ __restrict__ __syncthreads kernel device threadgroup constant")
        s.variables("threadIdx blockIdx blockDim gridDim warpSize")
        s.types("float2 float3 float4 half half2 half3 half4 int2 int3 int4 uint2 uint3 uint4 dim3 cudaError_t")
        return s
    }()

    // MARK: - Small DSLs

    static let prisma: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.cComments()
        s.typeDefiners("model enum type view")
        s.keywords("datasource generator")
        s.types("String Int BigInt Float Decimal Boolean DateTime Json Bytes Unsupported")
        s.constants("true false null")
        s.at = .attribute
        s.assignmentKeys = true
        return s
    }()

    static let mermaid: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineComment("%%")
        s.keywords("""
            graph flowchart sequenceDiagram classDiagram stateDiagram stateDiagram-v2 erDiagram journey gantt pie \
            gitGraph mindmap timeline quadrantChart requirementDiagram C4Context subgraph end participant actor \
            loop alt else opt par and rect note over left right of activate deactivate title section class state \
            direction TB TD BT RL LR click style classDef linkStyle autonumber critical break
            """)
        s.singleQuote = .none
        s.callHeuristic = false
        s.capitalized = nil
        s.allCapsConstants = false
        s.identDash = true
        return s
    }()

    static let dot: SyntaxLangSpec = {
        var s = SyntaxLangSpec(caseInsensitive: true)
        s.cComments()
        s.lineComment("#")
        s.keywords("digraph graph subgraph node edge strict")
        s.singleQuote = .none
        s.assignmentKeys = true
        s.capitalized = nil
        s.allCapsConstants = false
        return s
    }()

    static let gitignore: SyntaxLangSpec = {
        var s = SyntaxLangSpec()
        s.lineStartComments = [[35]]
        s.doubleQuote = false
        s.singleQuote = .none
        s.numbers = false
        s.callHeuristic = false
        s.capitalized = nil
        s.allCapsConstants = false
        return s
    }()
}
