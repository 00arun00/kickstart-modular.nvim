# When the pane becomes narrow

The title wraps, but should not crowd the text that follows. This note pushes
content near the width limit without relying on thousands of repeated rows.

## A long display

$$
\operatorname{Var}(X+Y)=\operatorname{Var}(X)+2\operatorname{Cov}(X,Y)+\operatorname{Var}(Y)
$$

The equation should remain complete. If fitting it requires a different
presentation, that choice should be deliberate and readable.

## A long literal line

```python
result = normalize_measurement(values=measurements, expected_value=estimated_mean, standard_deviation=estimated_scale)
```

## A constrained table

| Name | Mathematical meaning | Practical interpretation |
|:---|:---|:---|
| Standard deviation | $\sigma=\sqrt{\operatorname{Var}(X)}$ | The expected scale of deviations from the mean. |
| Conditional probability | $p(x\mid y)=\frac{p(y\mid x)p(x)}{p(y)}$ | How observing one quantity changes our belief about another. |

## Context matters

> A quotation narrows the available measure even further.
>
> $$
> \mathbb{E}[X+Y]=\mathbb{E}[X]+\mathbb{E}[Y]
> $$

The final line must remain readable at every tested width: NARROW_END.
