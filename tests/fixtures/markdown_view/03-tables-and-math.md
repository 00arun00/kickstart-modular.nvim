# Tables that remain readable

These tables mix short labels, numbers, long explanations, and mathematical
content. Read them at normal split width and after maximizing each pane.

## An ordinary table

| Item | Explanation |
| --- | --- |
| Ordinary prose | Default column alignment should read like prose, with a stable left edge. |
| A longer item name | A wrapped explanation should not become a centered stack of short lines. |

| ID | Item | Price | Explanation |
|:---|:---|---:|:---|
| 01 | Compact speaker | 249.00 | A short description. |
| 02 | A deliberately longer product name | 1,249.50 | A long explanation that should wrap naturally in its own column, without pushing neighbouring columns beyond the reading area. |
| 03 | Cable | 12.00 | Tiny values should not be forced into awkwardly tall rows. |

## The same structure with mathematics

| Quantity | Expression | Interpretation |
|:---|:---:|:---|
| Mean | $\mathbb{E}[X]=\mu$ | A compact expression in the middle column. |
| Variance | $\operatorname{Var}(X)=\sigma^2$ | A longer expression should preserve legible mathematical proportions. |
| Covariance | $\Sigma=\begin{pmatrix}1&\rho\\\rho&1\end{pmatrix}$ | A tall expression should receive enough vertical space without displacing another row's source location. |
| Probability | $p(x\mid y)$ | Inline mathematics belongs inside its cell and should not use page-level display alignment. |

## A wider comparison

| Case | Input | Operation | Output | Cost | Notes |
|:---|:---|:---|:---|---:|:---|
| A | Native text | Edit | Source | 1 | Editing remains native. |
| B | Mathematical Markdown | Typeset | Rich view | 2 | Wrapped prose and $x^2+y^2$ should share a coherent row. |
| C | A long descriptive input | Compare | A long descriptive output | 13 | At narrow widths the system should make a deliberate readability choice, rather than silently clipping content. |

This paragraph after all tables must remain visible and correctly synchronized.
