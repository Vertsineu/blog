#import "@hugo/utils:0.1.0": *

#let article(
  title: "",
  date: datetime.today(),
  draft: false,
  body,
) = {
  // for relative length unit
  set text(size: 18pt)

  // wrap raw content in a div/span with a class for styling
  show raw.where(block: false): html.span.with(class: "typst-raw-inline")
  show raw.where(block: true): html.div.with(class: "typst-raw-block")

  // equation was ignored during HTML export
  show math.equation.where(block: false): it => {
    html.span(role: "math", frame(it))
  }
  show math.equation.where(block: true): it => {
    html.figure(role: "math", style: "text-align: center;", frame(it))
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

  /// label for cutting content
  show <->: it => it

  /// labels for colors e.g. <red> <blue>
  show: body => dictionary(std)
    .pairs()
    .filter(((_, it)) => type(it) == std.color)
    .fold(body, (it, (str, color)) => {
      show label(str): text-colored.with(color)
      it
    })

  /// labels for alignment e.g. <center> <left>
  show: body => dictionary(std)
    .pairs()
    .filter(((_, it)) => type(it) == std.alignment)
    .fold(body, (it, (str, alignment)) => {
      show label(str): align.with(alignment)
      it
    })

  // label for hide
  show <hide>: hide

  // label for frame
  show <frame>: frame

  let prelude = metadata((
    title: title,
    date: date.display("[year]-[month]-[day]"),
    draft: draft,
  ))

  prelude
  body
}
