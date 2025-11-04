#import "@preview/ergo:0.2.0": *

#let week-header(
    weeknum,
    start-date: none,
) = {
    if start-date == none {
        start-date = datetime(
          year: 2025,
          month: 9,
          day: 27,
        ) + duration(days: 7 * (weeknum - 1))
    }
    let end-date = start-date + duration(days: 6)
    let title-text = [== Week #weeknum Notes]
    let date-text = [#start-date.display() to #end-date.display()]

    [
        #pagebreak()
        #v(1.5em, weak: true)
        #grid(
            columns: (1fr, 1fr),
            align(left,title-text),
            align(right,date-text),
        )
    ]
}

#let source                = ergo-statement.with(
  [Source],
  "algorithm"
)

#let quote                = ergo-statement.with(
  [Quote],
  "note"
)
