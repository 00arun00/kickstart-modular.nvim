# Equation rhythm and alignment

This note compares equivalent mathematics in different Markdown shapes. Inline
math such as $a+b=c$ belongs on the prose baseline. Display mathematics should
form a deliberate pause and use one consistent alignment policy.

## Equivalent standalone displays

**Separated delimiters.**

$$
a+b=c
$$

**Compact delimiters.**

$$a+b=c$$

**Longer display with separated delimiters.**

$$
\mathbb{E}[(X-\mu)^2]=\int_{-\infty}^{\infty}(x-\mu)^2p(x)\,dx=\sigma^2
$$

**Display embedded in a paragraph.** The statement before the equation must
survive: $$a+b=c$$ and this continuation must also remain readable.

## Mathematics inside containers

1. A list item introduces an equation. Its display should be centered within
   the list item's available width, not drift to the page's left margin.

   $$
   a+b=c
   $$

   This sentence continues the same item after the equation.

> A quotation has its own inset, but the same mathematical rhythm.
>
> $$
> a+b=c
> $$
>
> The quoted explanation should remain visually connected to its equation.

## Internal alignment is mathematical structure

The relation signs should align within this derivation, while the complete
display remains centered in the surrounding document.

$$
\begin{aligned}
\mathbb{E}[X]&=\mu\\
\operatorname{Var}(X)&=\mathbb{E}[X^2]-\mu^2\\
z&=\frac{x-\mu}{\sigma}
\end{aligned}
$$

$$
f(x)=\begin{cases}
x^2,&x\geq0\\
-x,&x<0
\end{cases}
\qquad
A=\begin{pmatrix}1&\rho\\\rho&1\end{pmatrix}
$$

## Source reveal remains deliberate

Move through this note in both panes. In the native source pane, enter Insert
mode inside an equation, make an edit, undo it, and return to Normal mode.
Adjacent prose and inline math $x_i^2+\frac{1}{2}$ should keep a comfortable
baseline, and the display above should not become a special navigation trap.
