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

#remark[
    These notes were made with the #link("https://typst.app/")[typst] typesetting language and the #link("https://github.com/EsotericSquishyy/ergo")[ergo package].
]

#week-header(5)
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
The above isn't a very official source, but it does contain some information on what the swift runtime actually does, which is good. "The Swift Runtime, a.k.a `libswiftCore`." This pretty immediately dives into SIL, so I might need to come back to it.

#source("A Swift Tour")[https://docs.swift.org/swift-book/documentation/the-swift-programming-language/guidedtour/]
I figure before I learn SIL I should brush up on swift syntax and type system.
- Pretty standard typed language. Functions are first class
- type `String?` allows for `String` values or `nil`
- closure syntax: `{ number in 3 * number }` or
    ```
    { (number: Int) -> Int in return 3 * number}
    ```
  or even shorter numbers.sorted `{ $0 > $1 }`
- inside methods, instance var access can be unqualified or use `self.`
- init function is named `init`. (also `deinit` exists). multiple inits may share function signatures, but must have different arg names.
  - #link("https://docs.swift.org/swift-book/documentation/the-swift-programming-language/initialization")[Initialization] has quite a few rules to ensure safety
- `class Subclass : Superclass{...}`; use `super.whatever`, manually call super.init. must use `override` qualifier for polymorphism.
- custom getter and setters for "fake" instance var. also `willSet` and `didSet` for code that needs to run around assignment
- enums can have methods. Use `Type.case` or just `.case` when type is infered
- structs are passed by value, classes are passed by reference
- async, await, Task blocks
- protocols are kinda like rust traits, extensions implement protocols for existing types
- errors implement Error protocol. functions that may throw an error are marked with throws.
- `try?` turns errors into optionals. defer plays nice with throw.
- generics use similar syntax to Rust

#source("SIL Documentation")[https://github.com/swiftlang/swift/blob/main/docs/SIL/SIL.md]
SIL has three representations:
- In memory: SIL is represented by data structures which are implemented in the compiler sources. Optimization passes use the in-memory representation of SIL.
- Textual: The compiler and related utilities can print and parse textual SIL files. Textual SIL files have the file extension `.sil`.
- Binary: SIL can be stored and read from binary files. Binary SIL files are called "swift-module" files and have the extension `.swiftmodule`. Note that the binary format is not stable. Swift-module files are not compatible between compiler versions.


#week-header(6)

SIL Documentation Continued:
- "A `.sil` file is a Swift source file with added SIL definitions."
- OSSA (Ownership Static Single-Assignment): each variable is assigned once, and ownership is checked to statically find memory leaks or use after free.
- Raw SIL vs Canonical SIL. Raw SIL may have dataflow errors and isn't optimized yet.
- SIL types start with `$`, SIL functions start with `@`, SIL values start with `%`
- SIL converts functions to basic blocks
  - all basic blocks end with a terminator
  - basic blocks take arguments
    - function arguments
    - forwarded arguments from the previous terminator
    - "phi arguments" these aprently have something to do with LLVM's phi nodes
  - in OSSA form, all arguments have ownership annotations
- Ownership types (also starts with `@`, don't confuse them with functions)
  - `@owned`: freestanding value is consumed exactly once during the function (by storing or destroying it typically)
  - `@guaranteed`: value that depends on another value's existance, such as a borrow.
  - `@unowned`: "A value that is only guaranteed to be instantaneously valid." Must be moved into `@owned` or `@guaranteed` being consumed.
  - Trivial values (such as int) don't have ownership
- WOOO LIFETIMES
  - less complicated than rust lifetimes
  - owned lifetimes start when an owned value is passed to the block (block or function?) or when an owned value is produced by an instruction
  - guaranteed lifetimes begin at a borrow, apply, or when a guaranteed value is passed to the function.
  - a lifetime must end exactly once along every control flow path
    - the one exception is `@guaranteed` values passed to a function which must survive the entire function
  - interior uses are any use of a value within its lifetime which is not the start or end
  - "forward-extended lifetime"
- borrowing
  - `%2 = begin_borrow %1` creates a borrow. `%1` must live until `%2` is unborrowed
  - `load_borrow` is very similar except the argument is an address and we load the memory at that address.
  - `store_borrow` stores an object on the stack, but has similar lifetime semantics otherwise
  - `partial_apply` baffles me and might make more sense when I know what apply does
- phi arguments
  - A type of argument that a basic block may take. These seem quite similar to forwarded values. I think the difference is that multiple different values may be passed to a phi argument.
  - E.g. after the end of a loop, we may be coming from either the interior of the loop or the beginning of the loop. the values from these two basic blocks need to be "merged" into one value with one lifetime.
  - speaking of lifetimes, there are some details about how owned, reborrowed and guaranteed values work
- A values must dominate instructions that use them. This essentially means that they are defined before they are used. Phi arguments make this a bit more complicated in practice.
- Joint post-dominance: sorta like lifetimes but for other things. e.g. all `alloc_stack` instructions must be followed by a `dealloc_stack` in every control path. This is called the instructions "scope".
- linking has a bunch of semantics that I don't quite understand
- each class has a VTable in the SIL file
- witness tables? like vtables but different. For protocols, which (as mentioned earlier) are like rust traits
  - "A witness table is emitted for every declared explicit conformance. Generic types share one generic witness table for all of their instances. Derived classes inherit the witness tables of their base class."
  - ok I think what that means is for every pair (protocol, class) such that the class "witnesses" the protocol (follows it), there is a table mapping the various methods that the protocol expects onto the actual functions implemented in the class.
  - each protocol may have a default witness table containing requirements (methods) with "resilient" default implementations. (this has something to do with implmentation order?????? or is this like metaphorical dependance order)

#week-header(7)
Back on that SIL grind, I should be skimming more
- global variables exist
- stack discipline
  - all stack deallocation functions must indicate the stack allocation function they correspond to
  - also they must nest properly

Ok that was all a (informative) detour to make sure I understand SIL before continuing to learn about the runtime. Let's get back to that one article that I was looking at earlier.

#source("The Swift Runtime - Your Silent Partner")[https://blog.jacobstechtavern.com/p/the-swift-runtime-your-silent-partner]
Since this article gives code examples, I want to see if I can follow along in `./tests/silent_partner`.
```bash
swiftc -emit-sil -O main.swift > sil.txt
```
Just based on what I leared from `SIL.md`, I can somewhat parse the output. We have a `main` function which has a single basic block, and a hidden global `@$s4main10test_classAA9TestClassCvp` which I think is just be our variable `test_class`.

This article starts by drilling down on how `alloc_ref` (which allocates space for an object (on the heap?)) is compiled.
- `IRGenSILFunction::visitAllocRefInst`
- `irgen::emitClassAllocation`
- `IRGenFunction::emitAllocObjectCall`
- `emitAllocatingCall`
- `IGM.getAllocObjectFunctionPointer()`
"When fully compiled into machine code, [`getAllocObjectFunctionPointer`] resolves as a pointer to the runtime ABI memory address of `swift_allocObject`."

ABI is "Application Binary Interface"

The runtime is sort of like a standard library `libswiftCore`, linked to the executable "on launch" (given that swift can be compiled, is it linked at runtime? how does that work?). There is a set of standard memory locations that the swift runtime functions are at.

"On iOS, the object is instantiated with swift_slowAllocTyped to allocate the required heap memory for the object." This seems like the type of stuff I'm looking for. What architectural differences does the runtime need to account for

Objects are reference counted (for garbage collection?).

#pagebreak()
== Next Steps
This section is a loose collection of "things I want to look at later."

definately look at:
- memory management
- "Advanced control flow with do, guard, defer, and repeat keywords" - About Swift
- optional types
- LLVM IR
- SIL guaranteed transformations

less important:
- SIL optimizations
- LLVM optimizations
