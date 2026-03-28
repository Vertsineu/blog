#import "@hugo/utils:0.1.0": *

#let article(
  title: "",
  date: datetime.today(),
  draft: false,
  body,
) = {
  // wrap raw content in a div/span with a class for styling
  show raw: it => {
    let fields = it.fields()
    if fields.block {
      html.div(class: "typst-raw-block", it)
    } else {
      html.span(class: "typst-raw-inline", it)
    }
  }

  // equation was ignored during HTML export
  show math.equation.where(block: false): it => {
    html.span(role: "math", html.frame(it))
  }
  show math.equation.where(block: true): it => {
    html.figure(role: "math", style: "text-align: center;", html.frame(it))
  }

  // make figure and table centered by default
  show figure: it => align(center, {
    let body = it.body
    let caption = align(center, it.caption)
    let output = if it.kind == table {
      caption
      body
    } else {
      body
      caption
    }
    html.figure(output)
  })

  show table: align.with(center)

  let prelude = metadata((
    title: title,
    date: date.display("[year]-[month]-[day]"),
    draft: draft,
  ))

  prelude
  body
}
