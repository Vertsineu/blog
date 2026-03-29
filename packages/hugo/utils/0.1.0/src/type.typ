/// This file contains utility functions for handling types in Typst.
/// These functions are used to convert between different types, 
/// such as lengths, alignments, and colors, 
/// to ensure that the values passed to the templates are in the correct format.

#let to-length(len) = {
  if type(len) == int {
    len * 1pt
  } else if type(len) == float {
    int(len) * 1pt
  } else if type(len) == length {
    len
  } else {
    panic("Unsupported length type, please use int, float, length!")
  }
}

// support: place-items, text-align, vertical-align, etc.
#let to-alignment(alignment) = {
  if type(alignment) != std.alignment {
    panic("Unsupported alignment type, please use a valid alignment!")
  }

  let x-align = alignment.x
  x-align = if x-align == center {
    "center"
  } else if x-align == left {
    "start"
  } else if x-align == right {
    "end"
  } else if x-align == start {
    "start"
  } else if x-align == end {
    "end"
  } else {
    "start" // fallback to start if none
  }

  let y-align = alignment.y
  y-align = if y-align == top {
    "start"
  } else if y-align == horizon {
    "center"
  } else if y-align == bottom {
    "end"
  } else {
    "start" // fallback to start if none
  }

  (x-align, y-align)
}

#let to-color(color) = {
  if type(color) != std.color {
    panic("Unsupported color type, please use a valid color!")
  }

  color.to-hex()
}
