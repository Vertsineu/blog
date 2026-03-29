#import "@hugo/utils:0.1.0": *
#import "@hugo/rewrites:0.1.0": *

#let article(
  title: "",
  description: "",
  tags: (),
  date: datetime.today(),
  weight: 10,
  draft: false,
  body,
  ..args,
) = {
  // for relative length unit
  set text(size: 18pt)

  // rewrite some built-in functions to better support HTML output
  show h: h-func
  show v: v-func
  show table: table-func
  show align: align-func
  show figure: figure-func
  show link: link-func
  show raw: raw-func
  show math.equation: math-equation-func

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
    description: description,
    tags: tags,
    date: date.display("[year]-[month]-[day]"),
    weight: weight,
    draft: draft,
    ..args.named(),
  ))

  prelude
  body
}
