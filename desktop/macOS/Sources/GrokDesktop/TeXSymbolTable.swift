import Foundation

/// Static TeX command tables. The data is kept as compact text and parsed once,
/// which keeps compile times low and makes the tables easy to scan.
enum TeXSymbolTable {
    struct Symbol {
        let scalar: UInt32
        let type: MathAtomType
    }

    struct LargeOperator {
        let scalar: UInt32
        let limits: MathLimits
    }

    struct NamedOperator {
        let text: String
        let limits: MathLimits
    }

    struct Accent {
        let scalar: UInt32
        let stretchy: Bool
        let under: Bool
    }

    // MARK: Ordinary symbols, binary operators, relations, punctuation

    private static let symbolData = """
    alpha 3B1 ord, beta 3B2 ord, gamma 3B3 ord, delta 3B4 ord, epsilon 3F5 ord, varepsilon 3B5 ord
    zeta 3B6 ord, eta 3B7 ord, theta 3B8 ord, vartheta 3D1 ord, iota 3B9 ord, kappa 3BA ord
    varkappa 3F0 ord, lambda 3BB ord, mu 3BC ord, nu 3BD ord, xi 3BE ord, omicron 3BF ord, pi 3C0 ord
    varpi 3D6 ord, rho 3C1 ord, varrho 3F1 ord, sigma 3C3 ord, varsigma 3C2 ord, tau 3C4 ord
    upsilon 3C5 ord, phi 3D5 ord, varphi 3C6 ord, chi 3C7 ord, psi 3C8 ord, omega 3C9 ord
    Gamma 393 ord, Delta 394 ord, Theta 398 ord, Lambda 39B ord, Xi 39E ord, Pi 3A0 ord, Sigma 3A3 ord
    Upsilon 3A5 ord, Phi 3A6 ord, Psi 3A8 ord, Omega 3A9 ord, Alpha 391 ord, Beta 392 ord, Epsilon 395 ord
    Zeta 396 ord, Eta 397 ord, Iota 399 ord, Kappa 39A ord, Mu 39C ord, Nu 39D ord, Omicron 39F ord
    Rho 3A1 ord, Tau 3A4 ord, Chi 3A7 ord, digamma 3DD ord, Digamma 3DC ord
    varGamma 1D6E4 ord, varDelta 1D6E5 ord, varTheta 1D6E9 ord, varLambda 1D6EC ord, varXi 1D6EF ord
    varPi 1D6F1 ord, varSigma 1D6F4 ord, varUpsilon 1D6F6 ord, varPhi 1D6F7 ord, varPsi 1D6F9 ord
    varOmega 1D6FA ord
    infty 221E ord, partial 2202 ord, nabla 2207 ord, forall 2200 ord, exists 2203 ord, nexists 2204 ord
    emptyset 2205 ord, varnothing 2300 ord, aleph 2135 ord, beth 2136 ord, gimel 2137 ord, daleth 2138 ord
    hbar 210F ord, hslash 210F ord, ell 2113 ord, Re 211C ord, Im 2111 ord, wp 2118 ord
    angle 2220 ord, measuredangle 2221 ord, sphericalangle 2222 ord, triangle 25B3 ord
    square 25A1 ord, Box 25A1 ord, blacksquare 25A0 ord, Diamond 25C7 ord, lozenge 25CA ord
    blacklozenge 29EB ord, bigstar 2605 ord, blacktriangle 25B2 ord, blacktriangledown 25BC ord
    triangledown 25BD ord, top 22A4 ord, bot 22A5 ord, prime 2032 ord, backprime 2035 ord
    checkmark 2713 ord, degree B0 ord, imath 1D6A4 ord, jmath 1D6A5 ord, S A7 ord, P B6 ord
    surd 221A ord, flat 266D ord, natural 266E ord, sharp 266F ord, clubsuit 2663 ord
    diamondsuit 2662 ord, heartsuit 2661 ord, spadesuit 2660 ord, mho 2127 ord, complement 2201 ord
    neg AC ord, lnot AC ord, copyright A9 ord, pounds A3 ord, eth F0 ord, Finv 2132 ord, Game 2141 ord
    circledR AE ord, circledS 24C8 ord, diagup 2571 ord, diagdown 2572 ord, # 23 ord, % 25 ord
    & 26 ord, $ 24 ord, _ 5F ord, dag 2020 ord, ddag 2021 ord, vdots 22EE ord, Vert 2016 ord
    vert 7C ord, | 2016 ord, backslash 5C ord, infin 221E ord, varkappa 3F0 ord, maltese 2720 ord
    yen A5 ord, euro 20AC ord, textdegree B0 ord, nabla 2207 ord, O D8 ord, o F8 ord, ss DF ord
    AE C6 ord, ae E6 ord, OE 152 ord, oe 153 ord, AA C5 ord, aa E5 ord, L 141 ord, l 142 ord
    pm B1 bin, mp 2213 bin, times D7 bin, div F7 bin, cdot 22C5 bin, ast 2217 bin, star 22C6 bin
    circ 2218 bin, bullet 2219 bin, oplus 2295 bin, ominus 2296 bin, otimes 2297 bin, oslash 2298 bin
    odot 2299 bin, circledast 229B bin, circledcirc 229A bin, circleddash 229D bin, boxplus 229E bin
    boxminus 229F bin, boxtimes 22A0 bin, boxdot 22A1 bin, cup 222A bin, cap 2229 bin, uplus 228E bin
    sqcup 2294 bin, sqcap 2293 bin, vee 2228 bin, wedge 2227 bin, lor 2228 bin, land 2227 bin
    setminus 2216 bin, smallsetminus 2216 bin, wr 2240 bin, diamond 22C4 bin, triangleleft 25C1 bin
    triangleright 25B7 bin, bigtriangleup 25B3 bin, bigtriangledown 25BD bin, dagger 2020 bin
    ddagger 2021 bin, amalg 2A3F bin, intercal 22BA bin, ltimes 22C9 bin, rtimes 22CA bin
    dotplus 2214 bin, centerdot 22C5 bin, barwedge 22BC bin, veebar 22BB bin, curlywedge 22CF bin
    curlyvee 22CE bin, divideontimes 22C7 bin, leftthreetimes 22CB bin, rightthreetimes 22CC bin
    Cap 22D2 bin, Cup 22D3 bin, doublecap 22D2 bin, doublecup 22D3 bin, gtrdot 22D7 rel
    lessdot 22D6 rel, circledplus 2295 bin, obar 233D bin, boxslash 29C4 bin, cdotp 22C5 punct
    ldotp 2E punct, colon 3A punct
    leq 2264 rel, le 2264 rel, geq 2265 rel, ge 2265 rel, leqslant 2A7D rel, geqslant 2A7E rel
    neq 2260 rel, ne 2260 rel, equiv 2261 rel, approx 2248 rel, cong 2245 rel, sim 223C rel
    simeq 2243 rel, propto 221D rel, varpropto 221D rel, ll 226A rel, gg 226B rel, lll 22D8 rel
    ggg 22D9 rel, subset 2282 rel, supset 2283 rel, subseteq 2286 rel, supseteq 2287 rel
    subsetneq 228A rel, supsetneq 228B rel, nsubseteq 2288 rel, nsupseteq 2289 rel
    subseteqq 2AC5 rel, supseteqq 2AC6 rel, subsetneqq 2ACB rel, supsetneqq 2ACC rel
    sqsubset 228F rel, sqsupset 2290 rel, sqsubseteq 2291 rel, sqsupseteq 2292 rel, in 2208 rel
    ni 220B rel, owns 220B rel, notin 2209 rel, notni 220C rel, perp 27C2 rel, parallel 2225 rel
    nparallel 2226 rel, mid 2223 rel, nmid 2224 rel, models 22A8 rel, vdash 22A2 rel, dashv 22A3 rel
    vDash 22A8 rel, Vdash 22A9 rel, Vvdash 22AA rel, nvdash 22AC rel, nvDash 22AD rel, nVdash 22AE rel
    prec 227A rel, succ 227B rel, preceq 2AAF rel, succeq 2AB0 rel, preccurlyeq 227C rel
    succcurlyeq 227D rel, precsim 227E rel, succsim 227F rel, asymp 224D rel, doteq 2250 rel
    doteqdot 2251 rel, triangleq 225C rel, coloneqq 2254 rel, coloneq 2254 rel, eqqcolon 2255 rel
    Coloneqq 2A74 rel, lesssim 2272 rel, gtrsim 2273 rel, lessapprox 2A85 rel, gtrapprox 2A86 rel
    nleq 2270 rel, ngeq 2271 rel, nless 226E rel, ngtr 226F rel, lneq 2A87 rel, gneq 2A88 rel
    lneqq 2268 rel, gneqq 2269 rel, nsim 2241 rel, ncong 2247 rel, napprox 2249 rel, nequiv 2262 rel
    approxeq 224A rel, bumpeq 224F rel, Bumpeq 224E rel, thicksim 223C rel, thickapprox 2248 rel
    backsim 223D rel, backsimeq 22CD rel, eqsim 2242 rel, smile 2323 rel, frown 2322 rel
    bowtie 22C8 rel, Join 22C8 rel, vartriangleleft 22B2 rel, vartriangleright 22B3 rel
    trianglelefteq 22B4 rel, trianglerighteq 22B5 rel, lhd 22B2 bin, rhd 22B3 bin, unlhd 22B4 bin
    unrhd 22B5 bin, between 226C rel, pitchfork 22D4 rel, Subset 22D0 rel, Supset 22D1 rel
    eqcirc 2256 rel, circeq 2257 rel, leqq 2266 rel, geqq 2267 rel, lessgtr 2276 rel, gtrless 2277 rel
    lesseqgtr 22DA rel, gtreqless 22DB rel, therefore 2234 rel, because 2235 rel, multimap 22B8 rel
    nprec 2280 rel, nsucc 2281 rel, npreceq 22E0 rel, nsucceq 22E1 rel, ntriangleleft 22EA rel
    ntriangleright 22EB rel, nsubset 2284 rel, nsupset 2285 rel, questeq 225F rel, measeq 225E rel
    stareq 225B rel, wedgeq 2259 rel, eqdef 225D rel, risingdotseq 2253 rel, fallingdotseq 2252 rel
    shortmid 2223 rel, shortparallel 2225 rel, nshortmid 2224 rel, nshortparallel 2226 rel
    varsubsetneq 228A rel, varsupsetneq 228B rel, smallsmile 2323 rel, smallfrown 2322 rel
    to 2192 rel, rightarrow 2192 rel, leftarrow 2190 rel, gets 2190 rel, Rightarrow 21D2 rel
    Leftarrow 21D0 rel, leftrightarrow 2194 rel, Leftrightarrow 21D4 rel, mapsto 21A6 rel
    longmapsto 27FC rel, mapsfrom 21A4 rel, longrightarrow 27F6 rel, longleftarrow 27F5 rel
    longleftrightarrow 27F7 rel, Longrightarrow 27F9 rel, Longleftarrow 27F8 rel
    Longleftrightarrow 27FA rel, uparrow 2191 rel, downarrow 2193 rel, updownarrow 2195 rel
    Uparrow 21D1 rel, Downarrow 21D3 rel, Updownarrow 21D5 rel, nearrow 2197 rel, searrow 2198 rel
    swarrow 2199 rel, nwarrow 2196 rel, hookrightarrow 21AA rel, hookleftarrow 21A9 rel
    rightleftharpoons 21CC rel, leftrightharpoons 21CB rel, rightharpoonup 21C0 rel
    rightharpoondown 21C1 rel, leftharpoonup 21BC rel, leftharpoondown 21BD rel, leadsto 21DD rel
    rightsquigarrow 21DD rel, twoheadrightarrow 21A0 rel, twoheadleftarrow 219E rel
    rightarrowtail 21A3 rel, leftarrowtail 21A2 rel, circlearrowleft 21BA rel, circlearrowright 21BB rel
    curvearrowleft 21B6 rel, curvearrowright 21B7 rel, Lsh 21B0 rel, Rsh 21B1 rel
    upharpoonright 21BE rel, upharpoonleft 21BF rel, downharpoonright 21C2 rel, downharpoonleft 21C3 rel
    restriction 21BE rel, leftleftarrows 21C7 rel, rightrightarrows 21C9 rel, leftrightarrows 21C6 rel
    rightleftarrows 21C4 rel, upuparrows 21C8 rel, downdownarrows 21CA rel, Lleftarrow 21DA rel
    Rrightarrow 21DB rel, looparrowright 21AC rel, looparrowleft 21AB rel, nrightarrow 219B rel
    nleftarrow 219A rel, nRightarrow 21CF rel, nLeftarrow 21CD rel, nleftrightarrow 21AE rel
    nLeftrightarrow 21CE rel, dashrightarrow 21E2 rel, dashleftarrow 21E0 rel, leftrightsquigarrow 21AD rel
    longleftrightarrows 27FA rel, iff 27FA rel, implies 27F9 rel, impliedby 27F8 rel
    lbrace 7B open, rbrace 7D close, { 7B open, } 7D close, langle 27E8 open, rangle 27E9 close
    lfloor 230A open, rfloor 230B close, lceil 2308 open, rceil 2309 close, lvert 7C open
    rvert 7C close, lVert 2016 open, rVert 2016 close, lbrack 5B open, rbrack 5D close
    ulcorner 231C open, urcorner 231D close, llcorner 231E open, lrcorner 231F close
    lgroup 27EE open, rgroup 27EF close, lmoustache 23B0 open, rmoustache 23B1 close
    llbracket 27E6 open, rrbracket 27E7 close, lBrack 27E6 open, rBrack 27E7 close
    R 211D ord, N 2115 ord, Z 2124 ord, Q 211A ord, C 2102 ord, reals 211D ord, Reals 211D ord
    natnums 2115 ord, Complex 2102 ord, cnums 2102 ord, empty 2205 ord, larr 2190 rel, rarr 2192 rel
    lrarr 2194 rel, harr 2194 rel, Larr 21D0 rel, Rarr 21D2 rel, Lrarr 21D4 rel, Harr 21D4 rel
    lArr 21D0 rel, rArr 21D2 rel, hArr 21D4 rel, uarr 2191 rel, darr 2193 rel, uArr 21D1 rel
    dArr 21D3 rel, Uarr 21D1 rel, Darr 21D3 rel, isin 2208 rel, sub 2282 rel, sube 2286 rel
    supe 2287 rel, lang 27E8 open, rang 27E9 close, plusmn B1 bin, sdot 22C5 bin, thetasym 3D1 ord
    weierp 2118 ord, image 2111 ord, real 211C ord, alef 2135 ord, alefsym 2135 ord, exist 2203 ord
    bull 2219 bin, clubs 2663 ord, diamonds 2662 ord, hearts 2661 ord, spades 2660 ord, Dagger 2021 bin
    sect A7 ord, notni 220C rel, varnothing 2300 ord, vcentcolon 2236 rel, dblcolon 2237 rel
    Colonapprox 2237 rel, colonapprox 2236 rel, ratio 2236 rel, minuscolon 2239 rel, bigcirc 25EF bin
    lozenge 25CA ord, textbackslash 5C ord, textasciitilde 7E ord, textbar 7C ord, textunderscore 5F ord
    """

    // MARK: Large operators

    private static let largeOperatorData = """
    sum 2211 d, prod 220F d, coprod 2210 d, bigcup 22C3 d, bigcap 22C2 d, bigvee 22C1 d, bigwedge 22C0 d
    bigoplus 2A01 d, bigotimes 2A02 d, bigodot 2A00 d, biguplus 2A04 d, bigsqcup 2A06 d, bigsqcap 2A05 d
    int 222B n, iint 222C n, iiint 222D n, iiiint 2A0C n, oint 222E n, oiint 222F n, oiiint 2230 n
    intop 222B d, smallint 222B n, varointclockwise 2232 n, ointctrclockwise 2233 n, sqint 2A16 n
    bigtimes 2A09 d, fint 2A0F n
    """

    // MARK: Named operators (text|limits)

    private static let namedOperatorData = """
    lim:lim:d, limsup:lim sup:d, liminf:lim inf:d, max:max:d, min:min:d, sup:sup:d, inf:inf:d
    det:det:d, Pr:Pr:d, gcd:gcd:d, lcm:lcm:d, argmax:arg max:d, argmin:arg min:d, injlim:inj lim:d
    projlim:proj lim:d, esssup:ess sup:d, essinf:ess inf:d, plim:plim:d
    sin:sin:n, cos:cos:n, tan:tan:n, cot:cot:n, sec:sec:n, csc:csc:n, arcsin:arcsin:n, arccos:arccos:n
    arctan:arctan:n, arccot:arccot:n, arcsec:arcsec:n, arccsc:arccsc:n, sinh:sinh:n, cosh:cosh:n
    tanh:tanh:n, coth:coth:n, sech:sech:n, csch:csch:n, arsinh:arsinh:n, arcosh:arcosh:n
    artanh:artanh:n, log:log:n, ln:ln:n, lg:lg:n, exp:exp:n, dim:dim:n, ker:ker:n, deg:deg:n
    hom:hom:n, arg:arg:n, tr:tr:n, Tr:Tr:n, rank:rank:n, diag:diag:n, sgn:sgn:n, sign:sign:n
    erf:erf:n, erfc:erfc:n, Var:Var:n, Cov:Cov:n, Corr:Corr:n, cov:cov:n, span:span:n, im:im:n
    id:id:n, Hom:Hom:n, End:End:n, Aut:Aut:n, Ker:Ker:n, Res:Res:n, lb:lb:n, th:th:n, sh:sh:n
    ch:ch:n, cth:cth:n, tg:tg:n, ctg:ctg:n, cosec:cosec:n, arctg:arctg:n, arcctg:arcctg:n
    """

    // MARK: Accents (scalar stretchy under)

    private static let accentData = """
    hat 302 0 0, widehat 302 1 0, tilde 303 0 0, widetilde 303 1 0, bar 304 0 0, vec 20D7 0 0
    dot 307 0 0, ddot 308 0 0, dddot 20DB 0 0, ddddot 20DC 0 0, acute 301 0 0, grave 300 0 0
    check 30C 0 0, widecheck 30C 1 0, breve 306 0 0, mathring 30A 0 0, overrightarrow 20D7 1 0
    overleftarrow 20D6 1 0, overleftrightarrow 20E1 1 0, overparen 23DC 1 0, wideparen 23DC 1 0
    underparen 23DD 1 1, underrightarrow 20EF 1 1, underleftarrow 20EE 1 1
    underleftrightarrow 34D 1 1, utilde 330 1 1, Vec 20D7 0 0, widebar 305 1 0, overarc 23DC 1 0
    """

    // MARK: Delimiters usable after \left, \right, \big…

    /// Command names (without backslash) usable as delimiters.
    private static let delimiterCommandData = """
    lbrack 5B, rbrack 5D, { 7B, } 7D, lbrace 7B, rbrace 7D, langle 27E8, rangle 27E9, lt 27E8, gt 27E9
    vert 7C, lvert 7C, rvert 7C, Vert 2016, lVert 2016, rVert 2016, | 2016, backslash 5C, lfloor 230A
    rfloor 230B, lceil 2308, rceil 2309, uparrow 2191, downarrow 2193, updownarrow 2195, Uparrow 21D1
    Downarrow 21D3, Updownarrow 21D5, lgroup 27EE, rgroup 27EF, lmoustache 23B0, rmoustache 23B1
    ulcorner 231C, urcorner 231D, llcorner 231E, lrcorner 231F, llbracket 27E6, rrbracket 27E7
    lBrack 27E6, rBrack 27E7, mid 2223, slash 2F
    """

    /// Characters usable directly as delimiters, mapped to the glyph we stretch.
    static let delimiterCharacters: [UInt32: UInt32] = [
        0x28: 0x28, 0x29: 0x29, 0x5B: 0x5B, 0x5D: 0x5D, 0x3C: 0x27E8, 0x3E: 0x27E9, 0x7C: 0x7C,
        0x2F: 0x2F, 0x27E8: 0x27E8, 0x27E9: 0x27E9, 0x2016: 0x2016, 0x230A: 0x230A, 0x230B: 0x230B,
        0x2308: 0x2308, 0x2309: 0x2309, 0x2191: 0x2191, 0x2193: 0x2193, 0x2195: 0x2195,
        0x21D1: 0x21D1, 0x21D3: 0x21D3, 0x21D5: 0x21D5, 0x27E6: 0x27E6, 0x27E7: 0x27E7,
        0x2223: 0x2223, 0x5C: 0x5C,
    ]

    // MARK: Negations for \not

    private static let negationData: [UInt32: UInt32] = [
        0x3D: 0x2260, 0x3C: 0x226E, 0x3E: 0x226F, 0x2264: 0x2270, 0x2265: 0x2271, 0x2261: 0x2262,
        0x223C: 0x2241, 0x2243: 0x2244, 0x2245: 0x2247, 0x2248: 0x2249, 0x2208: 0x2209,
        0x220B: 0x220C, 0x2282: 0x2284, 0x2283: 0x2285, 0x2286: 0x2288, 0x2287: 0x2289,
        0x2223: 0x2224, 0x2225: 0x2226, 0x227A: 0x2280, 0x227B: 0x2281, 0x22A2: 0x22AC,
        0x22A8: 0x22AD, 0x2203: 0x2204, 0x2192: 0x219B, 0x2190: 0x219A, 0x2194: 0x21AE,
        0x21D2: 0x21CF, 0x21D0: 0x21CD, 0x21D4: 0x21CE, 0x2AAF: 0x22E0, 0x2AB0: 0x22E1,
        0x2291: 0x22E2, 0x2292: 0x22E3, 0x224D: 0x226D, 0x2A7D: 0x2270, 0x2A7E: 0x2271,
        0x22B2: 0x22EA, 0x22B3: 0x22EB, 0x22B4: 0x22EC, 0x22B5: 0x22ED, 0x7C: 0x2224,
    ]

    // MARK: Parsed tables

    static let symbols: [String: Symbol] = {
        var table: [String: Symbol] = [:]
        for entry in entries(symbolData) {
            let parts = entry.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 3, let scalar = UInt32(parts[1], radix: 16) else { continue }
            table[String(parts[0])] = Symbol(scalar: scalar, type: atomType(parts[2]))
        }
        return table
    }()

    static let largeOperators: [String: LargeOperator] = {
        var table: [String: LargeOperator] = [:]
        for entry in entries(largeOperatorData) {
            let parts = entry.split(separator: " ")
            guard parts.count == 3, let scalar = UInt32(parts[1], radix: 16) else { continue }
            table[String(parts[0])] = LargeOperator(scalar: scalar, limits: parts[2] == "d" ? .displayOnly : .never)
        }
        return table
    }()

    static let namedOperators: [String: NamedOperator] = {
        var table: [String: NamedOperator] = [:]
        for entry in entries(namedOperatorData) {
            let parts = entry.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            table[String(parts[0])] = NamedOperator(text: String(parts[1]), limits: parts[2] == "d" ? .displayOnly : .never)
        }
        return table
    }()

    static let accents: [String: Accent] = {
        var table: [String: Accent] = [:]
        for entry in entries(accentData) {
            let parts = entry.split(separator: " ")
            guard parts.count == 4, let scalar = UInt32(parts[1], radix: 16) else { continue }
            table[String(parts[0])] = Accent(scalar: scalar, stretchy: parts[2] == "1", under: parts[3] == "1")
        }
        return table
    }()

    static let delimiterCommands: [String: UInt32] = {
        var table: [String: UInt32] = [:]
        for entry in entries(delimiterCommandData) {
            let parts = entry.split(separator: " ")
            guard parts.count == 2, let scalar = UInt32(parts[1], radix: 16) else { continue }
            table[String(parts[0])] = scalar
        }
        return table
    }()

    /// Atom class of a character typed directly (ASCII or Unicode).
    static let characterClasses: [UInt32: MathAtomType] = {
        var table: [UInt32: MathAtomType] = [:]
        for (_, symbol) in symbols where table[symbol.scalar] == nil || symbol.type != .ord {
            table[symbol.scalar] = symbol.type
        }
        let ascii: [(Character, MathAtomType)] = [
            ("+", .bin), ("-", .bin), ("*", .bin), ("=", .rel), ("<", .rel), (">", .rel), (":", .rel),
            (",", .punct), (";", .punct), ("(", .open), ("[", .open), (")", .close), ("]", .close),
            ("!", .close), ("?", .close), ("|", .ord), ("/", .ord), (".", .ord), ("{", .open), ("}", .close),
        ]
        for (c, t) in ascii { table[c.unicodeScalars.first!.value] = t }
        // Characters that appear with several classes above but are ordinary when typed.
        table[0x7C] = .ord
        table[0x2016] = .ord
        table[0x2032] = .ord
        table[0xAC] = .ord
        table[0x2212] = .bin
        table[0x2217] = .bin
        table[0x3A] = .rel
        for (_, op) in largeOperators { table[op.scalar] = .op }
        return table
    }()

    static let largeOperatorScalars: Set<UInt32> = Set(largeOperators.values.map(\.scalar))

    static func negation(of scalar: UInt32) -> UInt32? {
        negationData[scalar]
    }

    // MARK: Helpers

    private static func entries(_ data: String) -> [Substring] {
        data.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.drop(while: { $0 == " " }) }
            .filter { !$0.isEmpty }
    }

    private static func atomType(_ s: Substring) -> MathAtomType {
        switch s {
        case "op": return .op
        case "bin": return .bin
        case "rel": return .rel
        case "open": return .open
        case "close": return .close
        case "punct": return .punct
        case "inner": return .inner
        default: return .ord
        }
    }
}
