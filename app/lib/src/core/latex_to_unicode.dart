/// LaTeX → Unicode 的**保守**转换器，用于把行内公式渲染成可读文本。
///
/// 为什么需要它
/// ------------
/// 行内公式要真正嵌进一段文字里，唯一干净的做法是一个 `WidgetSpan`——但
/// `flutter_markdown` 不支持在段落内部塞组件（官方 API 只能在块级元素上用
/// `MarkdownElementBuilder` 替换，而替换块级元素会破坏它内部的 inline 记账，
/// 触发 `assert(_inlines.isEmpty)`）。
///
/// 所以这里换一条路：**行内公式转成 Unicode 文本**，直接随文字排版，
/// 不需要数学字体、不依赖任何组件、性能与渲染完全确定。
/// 代价是只能覆盖常用数学记号——这正是"保守"的含义：
/// **看不懂的公式绝不硬猜**，原样保留 LaTeX 源码，用户能立刻发现并改写成行间公式。
///
/// 行间公式（`$$...$$`）不走这里，仍由 `flutter_math_fork` 完整排版。
library;

/// 希腊字母与数学符号的命令 → Unicode。
const Map<String, String> _symbols = <String, String>{
  // 希腊字母（小写）
  r'\alpha': 'α', r'\beta': 'β', r'\gamma': 'γ', r'\delta': 'δ',
  r'\epsilon': 'ε', r'\varepsilon': 'ε', r'\zeta': 'ζ', r'\eta': 'η',
  r'\theta': 'θ', r'\vartheta': 'ϑ', r'\iota': 'ι', r'\kappa': 'κ',
  r'\lambda': 'λ', r'\mu': 'μ', r'\nu': 'ν', r'\xi': 'ξ', r'\pi': 'π',
  r'\varpi': 'ϖ', r'\rho': 'ρ', r'\sigma': 'σ', r'\tau': 'τ',
  r'\upsilon': 'υ', r'\phi': 'φ', r'\varphi': 'φ', r'\chi': 'χ',
  r'\psi': 'ψ', r'\omega': 'ω',
  // 希腊字母（大写）
  r'\Gamma': 'Γ', r'\Delta': 'Δ', r'\Theta': 'Θ', r'\Lambda': 'Λ',
  r'\Xi': 'Ξ', r'\Pi': 'Π', r'\Sigma': 'Σ', r'\Upsilon': 'Υ',
  r'\Phi': 'Φ', r'\Psi': 'Ψ', r'\Omega': 'Ω',
  // 关系符
  r'\le': '≤', r'\leq': '≤', r'\ge': '≥', r'\geq': '≥',
  r'\ne': '≠', r'\neq': '≠', r'\approx': '≈', r'\equiv': '≡',
  r'\sim': '∼', r'\simeq': '≃', r'\cong': '≅', r'\propto': '∝',
  r'\ll': '≪', r'\gg': '≫', r'\subset': '⊂', r'\subseteq': '⊆',
  r'\supset': '⊃', r'\supseteq': '⊇', r'\in': '∈', r'\notin': '∉',
  r'\ni': '∋', r'\perp': '⊥', r'\parallel': '∥',
  // 运算符
  r'\times': '×', r'\div': '÷', r'\pm': '±', r'\mp': '∓',
  r'\cdot': '·', r'\ast': '∗', r'\star': '⋆', r'\circ': '∘',
  r'\bullet': '•', r'\oplus': '⊕', r'\otimes': '⊗', r'\odot': '⊙',
  r'\cap': '∩', r'\cup': '∪', r'\setminus': '∖', r'\wedge': '∧',
  r'\vee': '∨', r'\neg': '¬', r'\land': '∧', r'\lor': '∨',
  // 箭头
  r'\to': '→', r'\rightarrow': '→', r'\leftarrow': '←', r'\gets': '←',
  r'\leftrightarrow': '↔', r'\Rightarrow': '⇒', r'\Leftarrow': '⇐',
  r'\Leftrightarrow': '⇔', r'\mapsto': '↦', r'\implies': '⟹',
  r'\iff': '⟺', r'\uparrow': '↑', r'\downarrow': '↓',
  // 大算符与其它
  r'\sum': 'Σ', r'\prod': '∏', r'\coprod': '∐',
  r'\int': '∫', r'\iint': '∬', r'\iiint': '∭', r'\oint': '∮',
  r'\bigcup': '⋃', r'\bigcap': '⋂', r'\bigoplus': '⨁', r'\bigotimes': '⨂',
  r'\bigvee': '⋁', r'\bigwedge': '⋀',
  r'\infty': '∞', r'\partial': '∂', r'\nabla': '∇',
  r'\forall': '∀', r'\exists': '∃', r'\nexists': '∄',
  r'\emptyset': '∅', r'\varnothing': '∅', r'\angle': '∠',
  r'\degree': '°', r'\prime': '′', r'\ldots': '…', r'\dots': '…',
  r'\cdots': '⋯', r'\vdots': '⋮', r'\ddots': '⋱',
  r'\hbar': 'ℏ', r'\ell': 'ℓ', r'\Re': 'ℜ', r'\Im': 'ℑ',
  r'\aleph': 'ℵ', r'\therefore': '∴', r'\because': '∵',
  // 函数名（保留为正体文本）
  r'\sin': 'sin', r'\cos': 'cos', r'\tan': 'tan',
  r'\cot': 'cot', r'\sec': 'sec', r'\csc': 'csc',
  r'\arcsin': 'arcsin', r'\arccos': 'arccos', r'\arctan': 'arctan',
  r'\sinh': 'sinh', r'\cosh': 'cosh', r'\tanh': 'tanh',
  r'\log': 'log', r'\ln': 'ln', r'\lg': 'lg', r'\exp': 'exp',
  r'\lim': 'lim', r'\max': 'max', r'\min': 'min', r'\sup': 'sup',
  r'\inf': 'inf', r'\det': 'det', r'\dim': 'dim', r'\ker': 'ker',
  r'\deg': 'deg', r'\gcd': 'gcd', r'\bmod': 'mod', r'\pmod': 'mod',
  // 空格类命令直接吃掉
  r'\,': '', r'\;': ' ', r'\:': ' ', r'\!': '', r'\quad': '  ', r'\qquad': '    ',
};

/// 上标 / 下标字符表。
const Map<String, String> _superscripts = <String, String>{
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶',
  '7': '⁷', '8': '⁸', '9': '⁹', '+': '⁺', '-': '⁻', '−': '⁻', '=': '⁼',
  '(': '⁽', ')': '⁾', 'n': 'ⁿ', 'i': 'ⁱ', 'a': 'ᵃ', 'b': 'ᵇ', 'c': 'ᶜ',
  'd': 'ᵈ', 'e': 'ᵉ', 'f': 'ᶠ', 'g': 'ᵍ', 'h': 'ʰ', 'j': 'ʲ', 'k': 'ᵏ',
  'l': 'ˡ', 'm': 'ᵐ', 'o': 'ᵒ', 'p': 'ᵖ', 'r': 'ʳ', 's': 'ˢ', 't': 'ᵗ',
  'u': 'ᵘ', 'v': 'ᵛ', 'w': 'ʷ', 'x': 'ˣ', 'y': 'ʸ', 'z': 'ᶻ',
  'T': 'ᵀ', 'A': 'ᴬ', 'B': 'ᴮ', 'D': 'ᴰ', 'E': 'ᴱ', 'I': 'ᴵ',
  'K': 'ᴷ', 'L': 'ᴸ', 'M': 'ᴹ', 'N': 'ᴺ', 'O': 'ᴼ', 'P': 'ᴾ', 'R': 'ᴿ',
  'U': 'ᵁ', 'V': 'ⱽ', 'W': 'ᵂ',
};

const Map<String, String> _subscripts = <String, String>{
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅', '6': '₆',
  '7': '₇', '8': '₈', '9': '₉', '+': '₊', '-': '₋', '−': '₋', '=': '₌',
  '(': '₍', ')': '₎', 'a': 'ₐ', 'e': 'ₑ', 'h': 'ₕ', 'i': 'ᵢ', 'j': 'ⱼ',
  'k': 'ₖ', 'l': 'ₗ', 'm': 'ₘ', 'n': 'ₙ', 'o': 'ₒ', 'p': 'ₚ', 'r': 'ᵣ',
  's': 'ₛ', 't': 'ₜ', 'u': 'ᵤ', 'v': 'ᵥ', 'x': 'ₓ',
};

/// 把一段 LaTeX 转成可读的 Unicode 文本。
///
/// 遇到无法可靠转换的结构（叠加上下标、矩阵、多字母上下标等）时返回 `null`，
/// 由调用方决定退回原始 LaTeX——**绝不输出错误的公式**。
String? latexToUnicode(String latex) {
  final source = latex.trim();
  if (source.isEmpty) return null;

  final out = StringBuffer();
  var i = 0;

  while (i < source.length) {
    final ch = source[i];

    // 注意顺序：结构性命令（\frac / \sqrt）必须在通用命令分支之前处理，
    // 否则会被 "_matchSymbol 找不到就返回 null" 直接吞掉。
    if (source.startsWith(r'\frac', i)) {
      final numerator = _readBraceArgument(source, i + 5);
      if (numerator == null) return null;
      final denominator = _readBraceArgument(source, numerator.$2);
      if (denominator == null) return null;
      final n = latexToUnicode(numerator.$1);
      final d = latexToUnicode(denominator.$1);
      if (n == null || d == null) return null;
      // 单字符不括起来，多字符用括号避免歧义
      final nText = n.length == 1 ? n : '($n)';
      final dText = d.length == 1 ? d : '($d)';
      out.write('$nText/$dText');
      i = denominator.$2;
      continue;
    }

    if (source.startsWith(r'\sqrt', i)) {
      final arg = _readBraceArgument(source, i + 5);
      if (arg == null) return null;
      final inner = latexToUnicode(arg.$1);
      if (inner == null) return null;
      out.write(inner.length == 1 ? '√$inner' : '√($inner)');
      i = arg.$2;
      continue;
    }

    // 文本模式：\text{...} / \mathrm{...} / \operatorname{...}
    // 内容按字面输出（展开内部命令），例如 \text{idx} -> idx。
    if (source.startsWith(r'\text', i) ||
        source.startsWith(r'\mathrm', i) ||
        source.startsWith(r'\operatorname', i) ||
        source.startsWith(r'\mbox', i)) {
      final cmdLength = source.startsWith(r'\operatorname', i)
          ? r'\operatorname'.length
          : source.startsWith(r'\mathrm', i)
              ? r'\mathrm'.length
              : source.startsWith(r'\mbox', i)
                  ? r'\mbox'.length
                  : r'\text'.length;
      final arg = _readBraceArgument(source, i + cmdLength);
      if (arg == null) return null;
      final inner = latexToUnicode(arg.$1);
      if (inner == null) return null;
      out.write(inner);
      i = arg.$2;
      continue;
    }

    // 其余反斜杠命令
    if (ch == r'\') {
      final match = _matchSymbol(source, i);
      if (match != null) {
        out.write(match.$1);
        i += match.$2;
        continue;
      }
      return null; // 未知命令：交给上层退回原始 LaTeX
    }

    // 上下标
    if (ch == '^' || ch == '_') {
      final table = ch == '^' ? _superscripts : _subscripts;
      final parsed = _readScriptArgument(source, i + 1);
      if (parsed == null) return null;
      final converted = _convertScript(parsed.$1, table);
      if (converted == null) return null;
      out.write(converted);
      i = parsed.$2;
      continue;
    }

    // 花括号只是分组，直接去掉
    if (ch == '{' || ch == '}') {
      i++;
      continue;
    }

    // 普通字符
    out.write(ch);
    i++;
  }

  final result = out.toString().trim();
  return result.isEmpty ? null : result;
}

/// 在 [index] 处匹配已知命令，返回 (替换文本, 消耗长度)。
(String, int)? _matchSymbol(String source, int index) {
  String? best;
  for (final key in _symbols.keys) {
    if (source.startsWith(key, index)) {
      // 命令后必须是非字母，避免把 \in 从 \infty 里截出来
      final after = index + key.length;
      if (after < source.length && _isLetter(source[after]) && _isLetter(key[key.length - 1])) {
        continue;
      }
      if (best == null || key.length > best.length) best = key;
    }
  }
  if (best == null) return null;
  return (_symbols[best]!, best.length);
}

bool _isLetter(String c) => RegExp(r'[A-Za-z]').hasMatch(c);

/// 读取 `^{...}` / `^x` 形式的上标参数，返回 (内容, 新下标)。
(String, int)? _readScriptArgument(String source, int index) {
  if (index >= source.length) return null;
  if (source[index] == '{') {
    return _readBraceArgument(source, index);
  }
  // 单个字符
  return (source[index], index + 1);
}

/// 读取 `{...}`，返回 (花括号内内容, 右花括号之后的下标)。
(String, int)? _readBraceArgument(String source, int index) {
  if (index >= source.length || source[index] != '{') return null;
  var depth = 0;
  for (var i = index; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return (source.substring(index + 1, i), i + 1);
    }
  }
  return null;
}

/// 把上标/下标内容逐字符映射；遇到没有对应字符的字母就放弃（返回 null）。
String? _convertScript(String content, Map<String, String> table) {
  // 先递归展开内容里的命令（例如 ^{-1} 里的 - 与 1）
  final buffer = StringBuffer();
  var i = 0;
  while (i < content.length) {
    final ch = content[i];
    if (ch == r'\') {
      final match = _matchSymbol(content, i);
      if (match == null) return null;
      buffer.write(match.$1);
      i += match.$2;
      continue;
    }
    buffer.write(ch);
    i++;
  }

  final plain = buffer.toString();
  final out = StringBuffer();
  for (final ch in plain.split('')) {
    final mapped = table[ch];
    if (mapped == null) return null; // 该字符没有上下标形式
    out.write(mapped);
  }
  return out.toString();
}
