#context {
  let points = query(<md-anchor>).map(it => {
    let pos = it.location().position()
    (source: it.value, page: pos.page, x: pos.x.pt(), y: pos.y.pt())
  })
  [#metadata(points) <md-map>]
}
