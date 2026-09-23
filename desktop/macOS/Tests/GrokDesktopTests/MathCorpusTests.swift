import AppKit
import XCTest
@testable import GrokDesktop

/// Real-world formulas in the style LLMs produce. Every one must render, have a
/// positive size, and never ask the math font for a glyph it doesn't have.
final class MathCorpusTests: XCTestCase {
    static let corpus: [String] = [
        // Algebra & classics
        #"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"#,
        #"e^{i\pi} + 1 = 0"#,
        #"e^{i\theta} = \cos\theta + i\sin\theta"#,
        #"(a+b)^2 = a^2 + 2ab + b^2"#,
        #"a^2 + b^2 = c^2"#,
        #"(x+y)^n = \sum_{k=0}^{n} \binom{n}{k} x^{n-k} y^{k}"#,
        #"\binom{n}{k} = \frac{n!}{k!(n-k)!}"#,
        #"\sum_{i=1}^{n} i = \frac{n(n+1)}{2}"#,
        #"\sum_{k=0}^{\infty} ar^k = \frac{a}{1-r}, \quad |r| < 1"#,
        #"\log_b(xy) = \log_b x + \log_b y"#,
        #"\ln(e^x) = x"#,
        #"x^{\frac{m}{n}} = \sqrt[n]{x^m}"#,
        #"|a + b| \le |a| + |b|"#,
        #"\frac{a}{b} \div \frac{c}{d} = \frac{a}{b} \times \frac{d}{c} = \frac{ad}{bc}"#,
        #"a \equiv b \pmod{m}"#,
        #"\gcd(a, b) \cdot \operatorname{lcm}(a, b) = |ab|"#,
        #"n! \approx \sqrt{2\pi n}\left(\frac{n}{e}\right)^n"#,
        #"\phi = \frac{1 + \sqrt{5}}{2}"#,
        #"F_n = \frac{\varphi^n - \psi^n}{\sqrt 5}"#,
        #"\lfloor x \rfloor \le x < \lfloor x \rfloor + 1"#,
        // Calculus
        #"\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}"#,
        #"\lim_{x \to 0} \frac{\sin x}{x} = 1"#,
        #"\lim_{n \to \infty} \left(1 + \frac{1}{n}\right)^n = e"#,
        #"f'(x) = \lim_{h \to 0} \frac{f(x+h) - f(x)}{h}"#,
        #"\frac{d}{dx}\left[ \int_a^x f(t)\,dt \right] = f(x)"#,
        #"\int_a^b f(x)\,dx = F(b) - F(a)"#,
        #"f(x) = \sum_{n=0}^{\infty} \frac{f^{(n)}(a)}{n!}(x-a)^n"#,
        #"e^x = 1 + x + \frac{x^2}{2!} + \frac{x^3}{3!} + \cdots"#,
        #"\sin x = x - \frac{x^3}{3!} + \frac{x^5}{5!} - \cdots"#,
        #"\int u\,dv = uv - \int v\,du"#,
        #"\frac{\partial^2 f}{\partial x \partial y} = \frac{\partial^2 f}{\partial y \partial x}"#,
        #"\nabla f = \left( \frac{\partial f}{\partial x}, \frac{\partial f}{\partial y}, \frac{\partial f}{\partial z} \right)"#,
        #"\iint_D \left( \frac{\partial Q}{\partial x} - \frac{\partial P}{\partial y} \right) dA = \oint_C P\,dx + Q\,dy"#,
        #"\int_0^{2\pi} \int_0^{\infty} e^{-r^2} r \, dr \, d\theta = \pi"#,
        #"\frac{dy}{dx} + P(x)y = Q(x)"#,
        #"\mathcal{L}\{f(t)\} = \int_0^\infty e^{-st} f(t)\,dt"#,
        #"\hat{f}(\xi) = \int_{-\infty}^{\infty} f(x)\, e^{-2\pi i x \xi}\, dx"#,
        #"\oint_C \mathbf{F} \cdot d\mathbf{r} = \iint_S (\nabla \times \mathbf{F}) \cdot d\mathbf{S}"#,
        #"\iiint_V (\nabla \cdot \mathbf{F})\, dV = \oiint_{\partial V} \mathbf{F} \cdot d\mathbf{S}"#,
        #"\left.\frac{df}{dx}\right|_{x=0} = 0"#,
        #"\dv{f}{x} = \pdv{g}{y}"#,
        #"y'' + \omega^2 y = 0"#,
        // Linear algebra
        #"A\mathbf{x} = \mathbf{b}"#,
        #"\begin{bmatrix} a & b \\ c & d \end{bmatrix} \begin{bmatrix} x \\ y \end{bmatrix} = \begin{bmatrix} ax + by \\ cx + dy \end{bmatrix}"#,
        #"\det(A) = \begin{vmatrix} a & b \\ c & d \end{vmatrix} = ad - bc"#,
        #"A^{-1} = \frac{1}{ad - bc} \begin{pmatrix} d & -b \\ -c & a \end{pmatrix}"#,
        #"I_3 = \begin{pmatrix} 1 & 0 & 0 \\ 0 & 1 & 0 \\ 0 & 0 & 1 \end{pmatrix}"#,
        #"A = U \Sigma V^\top"#,
        #"A = Q \Lambda Q^{-1}"#,
        #"\det(A - \lambda I) = 0"#,
        #"\langle \mathbf{u}, \mathbf{v} \rangle = \mathbf{u}^T \mathbf{v} = \sum_{i=1}^n u_i v_i"#,
        #"\|\mathbf{x}\|_2 = \sqrt{x_1^2 + x_2^2 + \cdots + x_n^2}"#,
        #"\|x\|_p = \left( \sum_{i=1}^n |x_i|^p \right)^{1/p}"#,
        #"\operatorname{tr}(AB) = \operatorname{tr}(BA)"#,
        #"\operatorname{rank}(A) + \dim \ker(A) = n"#,
        #"\mathbf{a} \times \mathbf{b} = \begin{vmatrix} \mathbf{i} & \mathbf{j} & \mathbf{k} \\ a_1 & a_2 & a_3 \\ b_1 & b_2 & b_3 \end{vmatrix}"#,
        #"\begin{pmatrix} a_{11} & a_{12} & \cdots & a_{1n} \\ a_{21} & a_{22} & \cdots & a_{2n} \\ \vdots & \vdots & \ddots & \vdots \\ a_{m1} & a_{m2} & \cdots & a_{mn} \end{pmatrix}"#,
        #"\left[\begin{array}{cc|c} 1 & 2 & 3 \\ 4 & 5 & 6 \end{array}\right]"#,
        #"R(\theta) = \begin{bmatrix} \cos\theta & -\sin\theta \\ \sin\theta & \cos\theta \end{bmatrix}"#,
        #"\mathbf{v} = \begin{Bmatrix} v_1 \\ v_2 \end{Bmatrix}, \quad \begin{Vmatrix} A \end{Vmatrix}"#,
        #"\bigl(\begin{smallmatrix} a & b \\ c & d \end{smallmatrix}\bigr)"#,
        // Probability & statistics
        #"P(A \mid B) = \frac{P(B \mid A)\,P(A)}{P(B)}"#,
        #"\mathbb{E}[X] = \sum_x x\,p(x)"#,
        #"\mathbb{E}_{x\sim p}[f(x)] = \int f(x)\,p(x)\,dx"#,
        #"\operatorname{Var}(X) = \mathbb{E}[X^2] - (\mathbb{E}[X])^2"#,
        #"\sigma = \sqrt{\frac{1}{N}\sum_{i=1}^{N}(x_i - \mu)^2}"#,
        #"f(x) = \frac{1}{\sigma\sqrt{2\pi}} e^{-\frac{1}{2}\left(\frac{x-\mu}{\sigma}\right)^2}"#,
        #"\mathcal{N}(\mu, \sigma^2)"#,
        #"X \sim \operatorname{Bin}(n, p)"#,
        #"P(X = k) = \binom{n}{k} p^k (1-p)^{n-k}"#,
        #"P(X = k) = \frac{\lambda^k e^{-\lambda}}{k!}"#,
        #"\bar{x} = \frac{1}{n}\sum_{i=1}^n x_i"#,
        #"\hat{\beta} = (X^\top X)^{-1} X^\top y"#,
        #"\operatorname{Cov}(X, Y) = \mathbb{E}[(X - \mu_X)(Y - \mu_Y)]"#,
        #"\rho_{X,Y} = \frac{\operatorname{Cov}(X,Y)}{\sigma_X \sigma_Y}"#,
        #"P\left(\bigcup_{i=1}^{\infty} A_i\right) = \sum_{i=1}^{\infty} P(A_i)"#,
        #"H(X) = -\sum_{x \in \mathcal{X}} p(x) \log_2 p(x)"#,
        #"D_{\mathrm{KL}}(P \,\|\, Q) = \sum_x P(x) \log \frac{P(x)}{Q(x)}"#,
        #"\Pr[|X - \mu| \geq k\sigma] \leq \frac{1}{k^2}"#,
        #"\bar{X}_n \xrightarrow{d} \mathcal{N}\left(\mu, \frac{\sigma^2}{n}\right)"#,
        #"p(\theta \mid \mathcal{D}) \propto p(\mathcal{D} \mid \theta)\, p(\theta)"#,
        #"\hat{\theta}_{\text{MLE}} = \operatorname*{arg\,max}_{\theta} \prod_{i=1}^n p(x_i \mid \theta)"#,
        // Machine learning
        #"\sigma(z) = \frac{1}{1 + e^{-z}}"#,
        #"\mathrm{softmax}(\mathbf{z})_i = \frac{e^{z_i}}{\sum_{j=1}^{K} e^{z_j}}"#,
        #"\mathcal{L}_{\text{CE}} = -\sum_{i=1}^{N} y_i \log(\hat{y}_i)"#,
        #"\mathrm{Attention}(Q, K, V) = \mathrm{softmax}\left(\frac{QK^\top}{\sqrt{d_k}}\right)V"#,
        #"\theta_{t+1} = \theta_t - \eta \nabla_\theta \mathcal{L}(\theta_t)"#,
        #"\mathrm{MSE} = \frac{1}{n}\sum_{i=1}^{n}(y_i - \hat{y}_i)^2"#,
        #"\mathrm{ReLU}(x) = \max(0, x)"#,
        #"h_t = \tanh(W_{hh} h_{t-1} + W_{xh} x_t + b_h)"#,
        #"\mathbf{y} = \sigma(W\mathbf{x} + \mathbf{b})"#,
        #"\min_{w, b} \frac{1}{2}\|w\|^2 \quad \text{s.t.} \quad y_i(w^\top x_i + b) \geq 1"#,
        #"\mathcal{L}(\theta) = \mathbb{E}_{q_\phi(z|x)}[\log p_\theta(x|z)] - D_{KL}(q_\phi(z|x) \| p(z))"#,
        #"m_t = \beta_1 m_{t-1} + (1 - \beta_1) g_t"#,
        #"\hat{m}_t = \frac{m_t}{1 - \beta_1^t}, \quad \theta_t = \theta_{t-1} - \frac{\alpha \hat{m}_t}{\sqrt{\hat{v}_t} + \epsilon}"#,
        #"\mathrm{LayerNorm}(x) = \gamma \odot \frac{x - \mu}{\sqrt{\sigma^2 + \epsilon}} + \beta"#,
        #"PE_{(pos, 2i)} = \sin\left(\frac{pos}{10000^{2i/d_{\text{model}}}}\right)"#,
        #"Q(s, a) \leftarrow Q(s, a) + \alpha \left[ r + \gamma \max_{a'} Q(s', a') - Q(s, a) \right]"#,
        #"V^\pi(s) = \mathbb{E}_\pi\left[\sum_{t=0}^{\infty} \gamma^t r_t \,\middle|\, s_0 = s\right]"#,
        #"\nabla_\theta J(\theta) = \mathbb{E}_{\tau \sim \pi_\theta}\left[\sum_t \nabla_\theta \log \pi_\theta(a_t|s_t) R(\tau)\right]"#,
        #"\text{precision} = \frac{TP}{TP + FP}, \quad \text{recall} = \frac{TP}{TP + FN}"#,
        #"F_1 = 2 \cdot \frac{\text{precision} \cdot \text{recall}}{\text{precision} + \text{recall}}"#,
        #"K(x, x') = \exp\left(-\frac{\|x - x'\|^2}{2\sigma^2}\right)"#,
        // Physics
        #"E = mc^2"#,
        #"F = ma"#,
        #"\mathbf{F} = q(\mathbf{E} + \mathbf{v} \times \mathbf{B})"#,
        #"\nabla \cdot \mathbf{E} = \frac{\rho}{\varepsilon_0}"#,
        #"\nabla \cdot \mathbf{B} = 0"#,
        #"\nabla \times \mathbf{E} = -\frac{\partial \mathbf{B}}{\partial t}"#,
        #"\nabla \times \mathbf{B} = \mu_0 \mathbf{J} + \mu_0 \varepsilon_0 \frac{\partial \mathbf{E}}{\partial t}"#,
        #"i\hbar \frac{\partial}{\partial t} \Psi(\mathbf{r}, t) = \left[ -\frac{\hbar^2}{2m} \nabla^2 + V(\mathbf{r}, t) \right] \Psi(\mathbf{r}, t)"#,
        #"\hat{H}|\psi\rangle = E|\psi\rangle"#,
        #"\langle \psi | \phi \rangle = \int \psi^*(x)\, \phi(x)\, dx"#,
        #"\Delta x \, \Delta p \geq \frac{\hbar}{2}"#,
        #"E = h\nu = \frac{hc}{\lambda}"#,
        #"\gamma = \frac{1}{\sqrt{1 - \frac{v^2}{c^2}}}"#,
        #"G_{\mu\nu} + \Lambda g_{\mu\nu} = \frac{8\pi G}{c^4} T_{\mu\nu}"#,
        #"ds^2 = -c^2 dt^2 + dx^2 + dy^2 + dz^2"#,
        #"PV = nRT"#,
        #"S = k_B \ln \Omega"#,
        #"\Delta G = \Delta H - T \Delta S"#,
        #"\vec{F}_{12} = k_e \frac{q_1 q_2}{r^2} \hat{r}"#,
        #"\ddot{x} + 2\zeta\omega_0 \dot{x} + \omega_0^2 x = 0"#,
        #"L = T - V, \quad \frac{d}{dt}\frac{\partial L}{\partial \dot{q}} - \frac{\partial L}{\partial q} = 0"#,
        #"Z = \sum_i e^{-\beta E_i}"#,
        #"\ket{\psi} = \alpha\ket{0} + \beta\ket{1}, \quad |\alpha|^2 + |\beta|^2 = 1"#,
        #"\rho = \sum_i p_i |\psi_i\rangle\langle\psi_i|"#,
        #"\sigma_x = \begin{pmatrix} 0 & 1 \\ 1 & 0 \end{pmatrix}"#,
        // Computer science
        #"\mathcal{O}(n \log n)"#,
        #"T(n) = 2T\left(\frac{n}{2}\right) + O(n)"#,
        #"T(n) = aT(n/b) + f(n)"#,
        #"\Theta(n^2), \quad \Omega(n), \quad o(1)"#,
        #"\sum_{i=0}^{\lfloor \log_2 n \rfloor} 2^i = 2^{\lfloor \log_2 n \rfloor + 1} - 1"#,
        #"H(n) = \sum_{k=1}^{n} \frac{1}{k} = \ln n + \gamma + O\!\left(\frac{1}{n}\right)"#,
        #"P \stackrel{?}{=} NP"#,
        #"f: \{0,1\}^n \to \{0,1\}"#,
        #"\neg (p \land q) \equiv \neg p \lor \neg q"#,
        #"\forall x \, \exists y \, (x < y)"#,
        #"A \cup B = \{x : x \in A \lor x \in B\}"#,
        #"|A \cup B| = |A| + |B| - |A \cap B|"#,
        #"\{x \in \mathbb{R} : x > 0\}"#,
        #"\mathbb{N} \subset \mathbb{Z} \subset \mathbb{Q} \subset \mathbb{R} \subset \mathbb{C}"#,
        #"\emptyset \neq A \subseteq B"#,
        #"\bigcap_{i \in I} A_i \subseteq \bigcup_{i \in I} A_i"#,
        #"C(n, k) = C(n-1, k-1) + C(n-1, k)"#,
        #"a \oplus b = (a \land \lnot b) \lor (\lnot a \land b)"#,
        #"\text{dp}[i][j] = \min(\text{dp}[i-1][j] + 1, \text{dp}[i][j-1] + 1)"#,
        #"\Pr[\text{collision}] \approx 1 - e^{-\frac{n^2}{2m}}"#,
        // Piecewise, aligned, cases
        #"|x| = \begin{cases} x & \text{if } x \geq 0 \\ -x & \text{if } x < 0 \end{cases}"#,
        #"f(n) = \begin{cases} n/2 & \text{if } n \equiv 0 \pmod{2} \\ 3n+1 & \text{if } n \equiv 1 \pmod{2} \end{cases}"#,
        #"\delta_{ij} = \begin{cases} 1, & i = j, \\ 0, & i \neq j. \end{cases}"#,
        #"\begin{aligned} (a+b)^2 &= (a+b)(a+b) \\ &= a^2 + ab + ba + b^2 \\ &= a^2 + 2ab + b^2 \end{aligned}"#,
        #"\begin{align} x + y &= 5 \\ 2x - y &= 1 \end{align}"#,
        #"\begin{align*} f(x) &= x^2 \\ f'(x) &= 2x \end{align*}"#,
        #"\begin{gathered} a = b \\ c = d \end{gathered}"#,
        #"\begin{equation} E = mc^2 \end{equation}"#,
        #"\begin{split} a &= b + c \\ &= d \end{split}"#,
        #"x &= 1 \\ y &= 2"#,
        #"a = b \\ c = d \\"#,
        #"\begin{dcases} \frac{1}{x} & x > 0 \\ 0 & \text{otherwise} \end{dcases}"#,
        #"\begin{array}{|c|c|} \hline x & y \\ \hline 1 & 2 \\ \hline \end{array}"#,
        #"\sum_{\substack{1 \le i \le n \\ i \ne j}} a_i"#,
        // Accents, decorations, misc
        #"\hat{x}, \tilde{y}, \bar{z}, \vec{v}, \dot{x}, \ddot{x}, \breve{u}, \check{c}, \acute{a}, \grave{e}, \mathring{A}"#,
        #"\widehat{ABC}, \widetilde{xyz}, \overline{AB}, \underline{cd}"#,
        #"\overrightarrow{AB} + \overleftarrow{CD} = \overleftrightarrow{EF}"#,
        #"\overbrace{1 + 2 + \cdots + n}^{n \text{ terms}}"#,
        #"\underbrace{a + a + \cdots + a}_{k \text{ times}} = ka"#,
        #"\overset{\text{def}}{=} \quad \underset{x}{\operatorname{argmin}} \quad a \stackrel{!}{=} b"#,
        #"\boxed{x^2 + y^2 = r^2}"#,
        #"\cancel{x} + \bcancel{y} + \xcancel{z}"#,
        #"A \xrightarrow{f} B \xleftarrow[g]{} C"#,
        #"\color{red}{x} + \textcolor{blue}{y} + \color{#00AA00} z"#,
        #"\textcolor[HTML]{FF8800}{\alpha} \colorbox{yellow}{boxed text}"#,
        #"\phantom{x}y\hphantom{z}\vphantom{\frac{1}{2}}w\mathstrut"#,
        #"\smash{\frac{a}{b}} + \smash[b]{g}"#,
        #"\displaystyle\sum_{i=1}^n i \quad \textstyle\sum_{i=1}^n i \quad \scriptstyle x \quad \scriptscriptstyle y"#,
        #"a\,b\:c\;d\!e\quad f\qquad g\enspace h\ i~j\hspace{1em}k"#,
        #"\cdots \ldots \dots \vdots \ddots \dotsc \dotsb"#,
        #"\infty \partial \nabla \forall \exists \nexists \emptyset \varnothing \aleph \beth \hbar \hslash \ell \Re \Im \wp"#,
        #"\angle \measuredangle \triangle \square \blacksquare \Box \top \bot \prime \backprime \checkmark \degree"#,
        ##"\imath \jmath \therefore \because \S \P \dagger \ddagger \# \% \& \$ \_ \{ \} \lbrace \rbrace"##,
        #"\surd \flat \natural \sharp \clubsuit \diamondsuit \heartsuit \spadesuit \mho \complement"#,
        #"\pm \mp \times \div \cdot \ast \star \circ \bullet \oplus \ominus \otimes \oslash \odot"#,
        #"\cup \cap \sqcup \sqcap \vee \wedge \setminus \smallsetminus \wr \diamond \triangleleft \triangleright \amalg"#,
        #"\leq \geq \leqslant \geqslant \neq \equiv \approx \cong \sim \simeq \propto \ll \gg"#,
        #"\subset \supset \subseteq \supseteq \subsetneq \supsetneq \sqsubseteq \sqsupseteq \in \ni \notin"#,
        #"\perp \parallel \mid \nmid \models \vdash \dashv \prec \succ \preceq \succeq \asymp \doteq"#,
        #"\triangleq \coloneqq \eqqcolon \lesssim \gtrsim \nleq \ngeq \not\equiv \not\sim \not\subset"#,
        #"\to \rightarrow \leftarrow \gets \Rightarrow \Leftarrow \leftrightarrow \Leftrightarrow \iff \implies \impliedby"#,
        #"\mapsto \longmapsto \longrightarrow \longleftarrow \longleftrightarrow \Longrightarrow \Longleftarrow \Longleftrightarrow"#,
        #"\uparrow \downarrow \updownarrow \Uparrow \Downarrow \nearrow \searrow \swarrow \nwarrow"#,
        #"\hookrightarrow \hookleftarrow \rightleftharpoons \leftrightharpoons \rightharpoonup \leadsto \twoheadrightarrow \rightarrowtail \circlearrowleft"#,
        #"\sum \prod \coprod \int \iint \iiint \oint \oiint \bigcup \bigcap \bigoplus \bigotimes \bigodot \biguplus \bigsqcup \bigvee \bigwedge"#,
        #"\lim \limsup \liminf \max \min \sup \inf \det \Pr \gcd \argmax \argmin"#,
        #"\sin \cos \tan \cot \sec \csc \arcsin \arccos \arctan \sinh \cosh \tanh \coth \log \ln \lg \exp \dim \ker \deg \hom \arg"#,
        #"\left( \left[ \left\{ \left\langle \left\lvert \left\lVert \left\lfloor \left\lceil x \right\rceil \right\rfloor \right\rVert \right\rvert \right\rangle \right\} \right] \right)"#,
        #"\left/ \frac{a}{b} \right\backslash \quad \left\uparrow \frac{a}{b} \right\Downarrow"#,
        #"\big( \Big[ \bigg\{ \Bigg| x \Bigg| \bigg\} \Big] \big) \bigl( \bigr) \bigm|"#,
        #"\mathrm{d}x \, \mathit{abc} \, \mathbf{A} \, \boldsymbol{\alpha} \, \bm{x} \, \mathbb{1} \, \mathbbm{1}"#,
        #"\mathcal{F} \mathscr{L} \mathfrak{su}(2) \mathsf{S} \mathtt{x} \mathnormal{y}"#,
        #"\text{Hello } \textrm{roman } \textit{italic } \textbf{bold } \texttt{mono } \textsf{sans} \mbox{box}"#,
        #"\text{where } x \text{ is } $y$ \text{ and } \operatorname{foo}(x)"#,
        #"\alpha \beta \gamma \delta \epsilon \varepsilon \zeta \eta \theta \vartheta \iota \kappa \varkappa \lambda \mu \nu \xi \pi \varpi \rho \varrho \sigma \varsigma \tau \upsilon \phi \varphi \chi \psi \omega \digamma"#,
        #"\Gamma \Delta \Theta \Lambda \Xi \Pi \Sigma \Upsilon \Phi \Psi \Omega \varGamma \varOmega"#,
        #"α + β ≤ γ → ∑_{i} x_i ∈ ℝ, ∀ε > 0"#,
        #"\frac{1}{\frac{1}{x} + \frac{1}{y}} \quad \tfrac{1}{2} \quad \dfrac{3}{4} \quad \cfrac{1}{1 + \cfrac{1}{2}}"#,
        #"{n \choose k} + {a \over b} + {a \atop b}"#,
        #"\sqrt{2}, \sqrt[3]{8}, \sqrt{\sqrt{x}}, \sqrt{1 + \sqrt{1 + \sqrt{1 + x}}}"#,
        #"x^{y^{z^w}} \quad a_{b_{c_d}} \quad x_i^2 \quad x^2_i \quad {}^{14}_{6}\mathrm{C}"#,
        #"\int\limits_0^1 f \quad \sum\nolimits_{i} a_i \quad \lim\limits_{x \to 0}"#,
        #"\abs{x} + \norm{v} + \bra{\phi} + \braket{\phi|\psi}"#,
        #"\left\{ \begin{array}{ll} a & b \\ c & d \end{array} \right."#,
        #"y = mx + b \tag{1}"#,
        #"\frac{a}{b} \label{eq:1} \nonumber"#,
        #"\newcommand{\R}{\mathbb{R}} f: \R^n \to \R"#,
        #"\unknowncommand{x} + y"#,
        #"x \in [0, 1) \cup (2, 3]"#,
        #"\sqrt{x^2+1}\,\Big|_{0}^{1}"#,
        #"\mathbf{x}^{(i)} \in \mathbb{R}^{d}"#,
        #"\vec{\nabla} \times \vec{A}"#,
        #"\text{中文 text and emoji-free}"#,
        #"\xrightarrow[\text{below}]{\text{above}} \quad \xRightarrow{x} \quad \xleftrightarrow{y}"#,
        #"\left\| \sum_{k} c_k \phi_k \right\|^2 = \sum_{k} |c_k|^2"#,
        #"\frac{\mathrm{d}}{\mathrm{d}t} \langle A \rangle = \frac{i}{\hbar} \langle [H, A] \rangle"#,
        // Chemistry (mhchem subset) and KaTeX shorthands
        #"\ce{2H2 + O2 -> 2H2O}"#,
        #"\ce{H2SO4 <=> 2H+ + SO4^2-}"#,
        #"\ce{CuSO4 * 5H2O}, \quad \Delta H = -286\,\mathrm{kJ/mol}"#,
        #"f: \R^n \to \R, \quad x \isin \N, \quad a \rarr b"#,
        #"\mathscr{L}\{f\} \quad \mathcal{L}(\theta)"#,
    ]

    func testCorpusRendersWithoutMissingGlyphs() {
        XCTAssertGreaterThanOrEqual(MathCorpusTests.corpus.count, 150)
        MathRenderer.debugClearCache()
        MathRenderer.debugResetMissingGlyphs()
        var failures: [String] = []
        for formula in MathCorpusTests.corpus {
            for display in [true, false] {
                guard let r = MathRenderer.render(formula, fontSize: 16, color: .textColor, display: display) else {
                    failures.append("nil: \(formula)")
                    continue
                }
                if !(r.width > 0 && r.height > 0 && r.ascent >= 0 && r.descent >= 0) {
                    failures.append("size: \(formula)")
                }
            }
        }
        XCTAssertEqual(failures, [])
        // The Chinese text is set with CoreText fallback in \text, never through the math font.
        let missing = MathRenderer.debugMissingScalars.map { String(format: "U+%04X", $0) }
        XCTAssertEqual(MathRenderer.debugMissingGlyphCount, 0, "missing: \(missing)")
    }

    func testEverySymbolTableEntryExistsInTheFont() throws {
        let font = try XCTUnwrap(MathFont.shared)
        var missing: [String] = []
        for (name, symbol) in TeXSymbolTable.symbols where !font.hasGlyph(for: symbol.scalar) {
            missing.append("\\\(name) U+\(String(symbol.scalar, radix: 16))")
        }
        for (name, op) in TeXSymbolTable.largeOperators where !font.hasGlyph(for: op.scalar) {
            missing.append("\\\(name)")
        }
        for (name, accent) in TeXSymbolTable.accents where !font.hasGlyph(for: accent.scalar) {
            missing.append("\\\(name)")
        }
        for (name, scalar) in TeXSymbolTable.delimiterCommands where !font.hasGlyph(for: scalar) {
            missing.append("\\\(name)")
        }
        XCTAssertEqual(missing.sorted(), [])
    }

    func testAlphabetsExistInTheFont() throws {
        let font = try XCTUnwrap(MathFont.shared)
        let styles: [MathFontStyle] = [.normal, .roman, .italic, .bold, .boldItalic, .boldSymbol, .script, .boldScript,
                                       .fraktur, .boldFraktur, .doubleStruck, .sansSerif, .sansSerifBold,
                                       .sansSerifItalic, .sansSerifBoldItalic, .monospace]
        var chars: [UInt32] = Array(0x41...0x5A) + Array(0x61...0x7A) + Array(0x30...0x39)
        chars += Array(0x391...0x3A1) + Array(0x3A3...0x3A9) + Array(0x3B1...0x3C9) + [0x2202, 0x3F5, 0x3D1, 0x3F0, 0x3D5, 0x3F1, 0x3D6]
        var missing: [String] = []
        for style in styles {
            for c in chars {
                let mapped = MathAlphabet.map(c, style: style)
                if !font.hasGlyph(for: mapped) { missing.append("\(style) U+\(String(mapped, radix: 16))") }
            }
        }
        XCTAssertEqual(missing, [])
    }

    /// Average uncached render time over the corpus (parse + layout + display list + NSImage).
    func testRenderPerformance() {
        let formulas = MathCorpusTests.corpus
        // Warm up font caches once.
        for f in formulas { _ = MathRenderer.render(f, fontSize: 15, color: .black, display: true) }
        var total: Double = 0
        var count = 0
        var worst: (Double, String) = (0, "")
        for iteration in 0..<5 {
            for f in formulas {
                let start = CFAbsoluteTimeGetCurrent()
                _ = MathRenderer.render(f, fontSize: 15 + CGFloat(iteration + 1) * 0.01, color: .black, display: true)
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                total += elapsed
                count += 1
                if elapsed > worst.0 { worst = (elapsed, f) }
            }
        }
        let average = total / Double(count) * 1000
        print(String(format: "MathKit: average uncached render %.3f ms over %d renders; worst %.3f ms: %@",
                     average, count, worst.0 * 1000, worst.1))
        XCTAssertLessThan(average, 2.0)

        let start = CFAbsoluteTimeGetCurrent()
        for f in formulas { _ = MathRenderer.render(f, fontSize: 15.01, color: .black, display: true) }
        let cached = (CFAbsoluteTimeGetCurrent() - start) / Double(formulas.count) * 1_000_000
        print(String(format: "MathKit: average cached lookup %.1f µs", cached))

        // Rasterizing the vector image at 2x (what a Retina view pays when it draws).
        let images = formulas.compactMap { MathRenderer.render($0, fontSize: 15.01, color: .black, display: true) }
        let context = CGContext(data: nil, width: 2400, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: 2, y: 2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let drawStart = CFAbsoluteTimeGetCurrent()
        for r in images { r.image.draw(in: CGRect(x: 0, y: 0, width: r.width, height: r.height)) }
        let draw = (CFAbsoluteTimeGetCurrent() - drawStart) / Double(images.count) * 1000
        NSGraphicsContext.restoreGraphicsState()
        print(String(format: "MathKit: average first draw at 2x %.3f ms", draw))
    }
}
