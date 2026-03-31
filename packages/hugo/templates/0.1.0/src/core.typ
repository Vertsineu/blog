#import "@hugo/utils:0.1.0": *
#import "@hugo/rewrites:0.1.0": *

#let article(
  // metadata
  title: "",
  description: "",
  tags: (),
  date: datetime.today(),
  weight: 10,
  draft: false,
  // outline(title: none)
  toc: true,
  // set text(lang: lang, region: region)
  lang: "zh",
  region: "cn",
  // bibliography(bytes(references.text), full: true)
  references: none,
  body,
  ..args,
) = {
  let prelude = metadata((
    title: title,
    description: description,
    tags: tags,
    date: date.display("[year]-[month]-[day]"),
    weight: weight,
    draft: draft,
    ..args.named(),
  ))

  // custom front matter for Typst
  prelude

  if "query" in sys.inputs and sys.inputs.query == "prelude" {
    // early return to avoid unnecessary rendering when only prelude is needed, e.g. front matter
    return
  }

  // for relative length unit
  // 18px = 13.5pt (96 dpi)
  set text(size: 13.5pt)
  set text(lang: lang, region: region)

  // rewrite some built-in functions to better support HTML output
  show h: h-func
  show v: v-func
  show table: table-func
  show align: align-func
  show figure: figure-func
  show link: link-func
  show raw: raw-func
  show math.equation: math-equation-func
  show outline: outline-func
  show outline.entry: outline-entry-func
  show image: image-func

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

  body

  if toc {
    outline(title: none)
  }

  if references != none {
    bibliography(bytes(references.text), full: true)
  }
}
