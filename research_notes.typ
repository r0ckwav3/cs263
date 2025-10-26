#import "@preview/ergo:0.2.0": *
#import "macros.typ": *

#show: ergo-init.with(
    colors:     ergo-colors.bootstrap,
    styles:     ergo-styles.sidebar1,
)

#show link: underline

// TODO: make this header cooler
#align(center)[
    = Wren Vandervelde CS263 Project
    = Swift and Mobile-focused runtimes (working title)
]
== Vision Statement
My goal for this project is to investigate the Swift language and runtime, specifically in respect to the language's use in mobile development. My first goal is to re-learn the details of Swift. I've worked with this language before, but I want to re-learn it with an eye towards what we've been learning in class, such as polymorphism and garbage collection. My next goal is to learn about the levels of bytecode that swift compiles into, such as Swift Intermediate Language (SIL) and the LLVM IL. I want to see what, if any, optimizations are made to aid in mobile execution. Finally, I want to investigate swift's cross-platform nature by running a number of benchmarks on different hardware, most likely my macbook, my iphone, and a larger machine such as CSIL.

#week-header(5)
#remark[
    These notes were made with the #link("https://typst.app/")[typst] typesetting language and the #link("https://github.com/EsotericSquishyy/ergo")[ergo package].
]
#source("Swift Compiler | Swift.org")[https://www.swift.org/documentation/swift-compiler/]
#source("The LLVM Compiler Infrastructure")[https://llvm.org/]

Compilation pipeline:
- Parsing - Parse code into an AST with no type checking
- Semantic analysis - Type inference and type checking; augments the AST with type information
- Clang importer - import clang modules (_note: what are these?_) and attach C / Obj-C interfaces.
- SIL generation - convert the AST into SIL (Swift Intermediate Language). _note: look at the #link("https://github.com/swiftlang/swift/blob/main/docs/SIL/SIL.md")[docs] later_
- SIL guaranteed transformations - something something dataflow, something something correctness? look at this later
- SIL optimizations - optimize the SIL based on swift-specific patterns.
- LLVM IR generation - generate LLVM IR
- LLVM optimization - use LLVM Core's optimizer on the IR
- Machine Code Generation - use LLVM's code generation

Based on this pipeline, now I'm a bit confused because this looks an awful lot like a compiled language, which presumably wouldn't have a runtime? There are still IRs so the project still works, but I want to get this straight. It looks like swift is compiled, but there are still references to "the Swift Runtime" across the website.

#source("About Swift | Swift.org")[https://www.swift.org/about/]
"Memory is managed automatically"
"Advanced control flow with do, guard, defer, and repeat keywords"
#quote[About Swift > Platform Support][
    Our goal is to provide source compatibility for Swift across all platforms, even though the actual implementation mechanisms may differ from one platform to the next. The primary example is that the Apple platforms include the Objective-C runtime, which is required to access Apple platform frameworks such as UIKit and AppKit. On other platforms, such as Linux, no Objective-C runtime is present, because it isn’t necessary.
]

#source("The Swift Runtime - Your Silent Partner")[https://blog.jacobstechtavern.com/p/the-swift-runtime-your-silent-partner]
The above isn't a very official source, but it does contain some information on what the swift runtime actually does, which is good.


== Next Steps
This section is a loose collection of "things I want to look at later."

definately look at:
- finish reading "The Swift Runtime - Your Silent Partner"
- #link("https://github.com/swiftlang/swift/blob/main/docs/SIL/SIL.md")[SIL docs]
- memory management
- "Advanced control flow with do, guard, defer, and repeat keywords" - About Swift
- optional types
- LLVM IR
- SIL guaranteed transformations

less important:
- SIL optimizations
- LLVM optimizations
