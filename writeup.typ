#import "@preview/cetz:0.4.2"
#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

#set page(
  "us-letter",
  margin: 1in,
  header: context {
    if counter(page).get().first() > 1 {
      grid(columns: (80%, 20%),
        align: (left, right),
        [_On the Implementation and Performance of Swift's Weak References_], [Wren Vandervelde]
      )
    }
  }
)

#set heading(numbering: "1.1")
#show figure.caption: emph
#show figure: it => {
  let spacing = 1em

  if it.placement == none {
    block(it, inset: (y: spacing))
  } else {
    place(
      it.placement,
      float: true,
      clearance: spacing,
      block(align(center, it), spacing: spacing, width: 100%),
    )
  }
}

// TODO: make this title look good
#align(center)[
  #set text(weight: "bold", size: 14pt)
  On the Implementation and Performance of Swift's Weak References \
  #set text(weight: "bold", size: 10pt)
  Wren Vandervelde \
  CMPSC 263 F25
]

= Abstract
Swift's primary runtime, usually just called the Swift runtime, implements garbage collection via pure reference counting. This means that the garbage collector never needs to interrupt the program to either sweep or copy the memory, but it leaves the system vulnerable to strong reference cycles. Two object which reference each other will never be cleaned because they always have positive strong reference counts. To break strong reference cycles, swift introduces three other reference types which don't increment the strong reference count. These references, which I will refere to collectively as "weak reference types" each have their own tradeoffs. Weak references require allocating and deallocating a side table entry when they are first used, unowned references may keep the object's memory alive for longer than expected, and unsafe references can introduce use-after-free vulnerabilities into the code. The goal of my project was to learn about the API of these references, find their implementation details, and benchmark their performance on a number of common operations.

= The Swift Language
Swift is a high-level language originally developed by Apple and then open-sourced in 2015#footnote[https://www.swift.org/about/]. Swift advertises itself as a general purpose language, although one of its most notable uses is in application development for Apple's primary platforms -- iOS, macOS, watchOS, and tvOS. In contrast to its predecessor Objective-C, one of Swift's stated goals is safety, which it implements via an automatic reference counting garbage collector.

== Compiling Swift
To understand how Swift's memory management works, we first need to understand the nature of Swift's compilation flow and runtime. The first step of this workflow is parsing and semantic analysis#footnote[https://www.swift.org/documentation/swift-compiler/]. Swift is a strongly typed language with modern type inference, so these two steps parse the high-level swift code and propate type information through the AST. Also in this step is the Clang importer, which semantically links clang modules to the code so that they can be part of the type inference and verification.

The next step of compilation is SIL generation. Swift Intermediate Language (SIL), as the name suggests, acts as an intermediary step between high-level swift code and the lower compilation steps. Much like Java bytecode, SIL looks much more like assembly code, with each line containing an opcode with arguments#footnote[https://github.com/swiftlang/swift/blob/main/docs/SIL/SIL.md]. For control flow within functions, SIL uses basic blocks, each of which have their own local variables, arguments and forwarded values for the next basic block. Despite the aparent simplicity of the instructions, it is just as strongly typed than swift, and automatically generates additional verification information such as object lifetimes and ownership information. SIL is also a Static Single Assignment (SSA) language, meaning that each variable is assigned exactly once. At this step of the process, a number of transformations and optimizations are also applied. Relevant to this project, there are actually a number of optimizations focused on reference counting. For the sake of simplicity, I will not be considering these, but they may be worth investegating in the future.

// TODO: do I include an example of SIL here? it's pretty cool to look at the basic blocks at least

Finally, the SIL is lowered to LLVM IR, yet another intermeidate representation, which can then be compiled to a native executable by LLVM. SIL and LLVM IR can look similar but have a few key differences. For one, SIL is type safe and uses swift abstractions such as object lifetimes wheras LLVM IR is a general intermediate language. SIL is also hardware agnostic while LLVM IR contains hardware-specific information.

== The Swift Runtime

Astute readers may notice that at the end of the compilation process, we end up with an executable binary. So why do we need a runtime? And how does the runtime manage memory the program during execution?

What we refer to as the Swift runtime is a section of the Swift standard library which is dynamically linked to the executable at runtime#footnote[https://www.swift.org/documentation/standard-library/]. For example, lets see how the runtime manages a program which creates an object.

#figure(
  text(size: 8pt)[
    #grid(
      columns: 2,
      align: left,
      inset: 1em,
      stroke: none,
      [Source Code],
      ```swift
class A { }
let obj = A()
      ```,
      grid.hline(),
      [SIL],
      ```
[...]
alloc_global @$s3sil3objAA1ACvp
%3 = global_addr @$s3sil3objAA1ACvp : $*A
%4 = alloc_ref $A
debug_value %4, let, name "self", argno 1
%6 = end_init_let_ref %4
store %6 to %3
[...]
      ```,
      grid.hline(),
      [LLVM IR],
      ```
[...]
%4 = call noalias ptr @swift_allocObject(ptr %3, i64 16, i64 7) #2
store ptr %4, ptr @"$s18llvmir_unoptimized3objAA1ACvp", align 8
[...]
      ```
    )
  ],
  caption: [Compilation steps of allocation ],
) <compilation_steps>

We start with some of the simplest swift code that will allocate an object on the heap. In @compilation_steps we create a class `A` and instantiate an object `obj`, which will be heap-allocated. The compiler then translates this to nearly one hundred lines of SIL. A bunch of these lines are autogenerated code for our class `A`. We find two autogenerated `init` functions and two autogenerated `deinit` functions which are infered from our empty class definition. The function we're interested in is the `main()` function, which contains the expanded version of the line `let obj = A()`. Due to SIL being SSA, all of our variables have been renamed, but we can see where they went. For example, note that `@$s3sil3objAA1ACvp` corresponds to our global variable `obj`. The two most important lines in this code are `alloc_ref` and `end_init_let_ref`, which is where we are allocating space for the object on the heap and declaring the object initialized respectively. Since memory is managed by the runtime, we know that this `alloc_ref` instruction must eventually talk to the runtime.

Luckily in the SIL to LLVM IR translation, we get to keep most of the variable names, so finding the equivalent to `alloc_ref` is comparatively simple. I've cut off the allocation of the global variable since it's not what we're interested in, but even still, the latter four lines of SIR are lowered to only two lines of LLVM IR. The first line is what `alloc_ref` is translated into, and it's the runtime hook we're looking for. Specifically, `alloc_ref` is translated to a function call to `@swift_allocObject`, a function defined in the runtime portion of the standard library.

The rest of the Swift runtime is implemented similarly. Memory operations in swift are translated to memory management instructions in SIL which are then lowered to into runtime function calls.

= Solving Reference Cycles
As mentioned earlier, the Swift runtime manages memory via a reference counting garbage collector. While this can be less intrusive than other garbage collection methods, reference counting has the pretty serious tradeoff that it leaks strong reference cycles. Consider a doubly linked list defined in @dll_code using the default "strong" references provided in swift. At the end of this code block, neither `Listnode` object is reachable from our roots (`a` and `b`), but both have a nonzero reference count because they point to each other.

#figure(
  ```swift
  class ListNode{
    var val: String
    init(val: String) { self.val = val }
    var next: ListNode?
    var prev: ListNode?
  }
  var a: ListNode? = ListNode("a")
  var b: ListNode?  = ListNode("b")
  a!.next = b
  b!.prev = a
  a = nil
  b = nil
  ```,
  caption: [A doubly linked list]
)<dll_code>

#figure(
  cetz.canvas(
    length: 0.75cm, {
    import cetz.draw: *

    rect((0,2.6),(4,3.6), fill: gray, name: "header_a")
    rect((0,0),(4,2.6), name: "body_a")
    content("header_a.center", `ListNode (rc=2)`)
    content("body_a.north", `val: "a"`, anchor:"north", padding:(top:0.4, rest:0.2), name: "attr1_a")
    content("attr1_a.south", `prev: nil`, anchor:"north", padding:0.2, name: "attr2_a")
    content("attr2_a.south", `next: ptr`, anchor:"north", padding:0.2, name: "attr3_a")

    rect((8,2.6),(12,3.6), fill: gray, name: "header_b")
    rect((8,0),(12,2.6), name: "body_b")
    content("header_b.center", `ListNode (rc=2)`)
    content("body_b.north", `val: "b"`, anchor:"north", padding:(top:0.4, rest:0.2), name: "attr1_b")
    content("attr1_b.south", `prev: ptr`, anchor:"north", padding:0.2, name: "attr2_b")
    content("attr2_b.south", `next: nil`, anchor:"north", padding:0.2, name: "attr3_b")

    content((2,5), `var a`, padding:0.2, name: "var_a")
    content((10,5), `var b`, padding:0.2, name: "var_b")

    set-style(mark: (start: none, end: ">"))
    line("var_a", "header_a")
    line("var_b", "header_b")
    line("attr3_a", "header_b.west")
    line("attr2_b", "header_a.east")
  }),
  caption: [A strong reference cycle]
)<dll_strong_cycle>

The way that swift solves this is by introducing a number of "weak" references--as opposed to the normal "strong" references#footnote("https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/"). These three references are weak references, unowned references, and unsafe unowned references, which I will refer to as simply "unsafe references". All three of these can point to an object without increasing its reference count. What this also means is that all of these weak reference types may end up pointing to an object whose reference count has reached 0 and therefore has been deinitialized. How the three weak reference types handle that case is their main distinguishing feature:
- Weak references must be optional types and, when the referenced object is deinitialized, are automatically set to `nil`.
- Unowned references panic when a user tries to reference them after deallocation
- Unsafe references don't have any checks, and may allow the user to make use-after-free errors

Unsafe references, like the name suggests, violate the memory safety of swift and are therefore highly discouraged. When choosing between the other two options, swift suggests using the concept of ownership and lifetimes. If there are two (or more) objects which may cause a reference cycle, one of them should be designated as the "owner" of the other object and is typically the object with the longer lifetime -- the one which is created first and used last. If the owned object has a stictly shorter lifetime than the owner, then it should have a unowned reference, since there's no risk of panicking. On the other hand, if the owned object might live longer than the owner, weak references should be used.

For example, in our linked list we typically keep a reference to the head, so we should make the `next` reference be strong. However, we may want to pop the head of the list and then keep around everything else, so the `prev` reference should be weak. In @dll_code_weak we have the updated class definition, which leads to the references in @dll_weak_cycle.

#figure(
  ```swift
  class ListNode{
    var val: String
    init(val: String) { self.val = val }
    var next: ListNode?
    weak var prev: ListNode?
  }
  ```,
  caption: [An updated doubly linked list]
)<dll_code_weak>

#figure(
  cetz.canvas(
    length: 0.75cm, {
    import cetz.draw: *

    rect((0,2.6),(4,3.6), fill: gray, name: "header_a")
    rect((0,0),(4,2.6), name: "body_a")
    content("header_a.center", `ListNode (rc=1)`)
    content("body_a.north", `val: "a"`, anchor:"north", padding:(top:0.4, rest:0.2), name: "attr1_a")
    content("attr1_a.south", `prev: nil`, anchor:"north", padding:0.2, name: "attr2_a")
    content("attr2_a.south", `next: ptr`, anchor:"north", padding:0.2, name: "attr3_a")

    rect((8,2.6),(12,3.6), fill: gray, name: "header_b")
    rect((8,0),(12,2.6), name: "body_b")
    content("header_b.center", `ListNode (rc=2)`)
    content("body_b.north", `val: "b"`, anchor:"north", padding:(top:0.4, rest:0.2), name: "attr1_b")
    content("attr1_b.south", `prev: ptr(weak)`, anchor:"north", padding:0.2, name: "attr2_b")
    content("attr2_b.south", `next: nil`, anchor:"north", padding:0.2, name: "attr3_b")

    content((2,5), `var a`, padding:0.2, name: "var_a")
    content((10,5), `var b`, padding:0.2, name: "var_b")

    set-style(mark: (start: none, end: ">"))
    line("var_a", "header_a")
    line("var_b", "header_b")
    line("attr3_a", "header_b.west")
    line("attr2_b", "header_a.east", stroke: (dash: "dashed"))
  }),
  caption: [Solving the reference cycle with weak references]
)<dll_weak_cycle>

Once `a` and `b` are unassigned, object B will drop down to 1 reference (from object A next), but object A now has a reference count of 0 since the weak reference from object B doesn't contribute to the count. This leads to object A being deinitialized, removing the reference to object B. This in turn brings B's reference count down to 0, so both objects are correctly deinitialized and deallocated.

== Weak Reference Implementation
Now that we understand how weak references work, we can start to understand how they're implemented. Reference counting with only strong references creates a straightforward and elegant system. Each object has one reference count stored as metadata and is deinitialized exactly when its reference count drops to zero. A reference counted runtime system with weak references cannot be as simple. For instance, when an unowned reference tries to access an object with no more strong references, it needs to panic. How does it "know" that the object has been deinitialized? Presumably there's a flag somewhere, but now that's extra state that we didn't need to store previously. And now _that_ state needs to be deallocated somehow when there are no more unowned references.

Since unowned references are the simpler of the two, let's start with looking at their implementation. Rather than containing a basic reference count in the object's header, each heap-allocated `HeapObject` in Swift contains a `InlineRefCounts` struct, containing a strong reference count, an unowned reference count, and the object's "state", which follows the state machine in @object_state_machine. We abbreviate strong reference count as SRC, unowned reference count as URC, and (when we add them in) weak reference count as WRC.

#figure(
  {
    set text(8pt)
    diagram(
      node-stroke: 1pt,

      node((0,0), `INIT`, radius: 2.5em),
      node((0,1), `LIVE`, radius: 2.5em),
      node((2,1), `DEINITING`, radius: 2.5em),
      node((4,1), `DEINITED`, radius: 2.5em),
      node((6,1), `DEAD`, radius: 2.5em),

      node((0,2), `LIVE`, radius: 2.5em),
      node((2,2), `DEINITING`, radius: 2.5em),
      node((4,2), `DEINITED`, radius: 2.5em),
      node((6,2), `FREED`, radius: 2.5em),

      {
        let tint(c) = (stroke: c, fill: rgb(..c.components().slice(0,3), 5%), inset: 8pt)
    		node(text(teal, align(bottom)[with side table]), enclose: ((0,2), (6,2)), ..tint(teal))
      },

      edge((0,0), (0,1), "->", $"RCs" = 1$, label-side: left),
     	edge((0,1), (2,1), "->", $"SRC" = 0$),
     	edge((2,1), (4,1), "->", $"URC" - 1$),
     	edge((4,1), (6,1), "->", $"URC" = 0$),

      edge((0,1), (0,2), "->", $"WRC" != 0$, label-side: left),
      // edge((2,1), (2,2), "->", $"WRC" != 0$, label-side: left),
      edge((6,2), (6,1), "->", $"WRC" = 0$, label-side: left),

     	edge((0,2), (2,2), "->", $"SRC" = 0$),
     	edge((2,2), (4,2), "->", $"URC" - 1$),
     	edge((4,2), (6,2), "->", $"URC" = 0$),
     	edge((4,2), (6,2), "->", $"WRC" - 1$, label-side: right),
    )
  },
  caption: [The object lifecycle state machine]
)<object_state_machine>

An object's normal state is `LIVE`, where all operations are valid. Once the strong reference count reaches zero, instead immediately deallocating the object, we move to the `DEINITING` state and call the user-specified deinit function. During this time, attempting to dereference an unowned referece will result in an error. The auto-generated deinit function also removes all the references inside the object during this stage. Once the deinit function finishes, the object moves to the `DEINITED` state and the unowned reference count is decremented. Note that the URC starts at 1, so the unowned refrence count now accurately counts the number of unowned references. Unowned references to the object may still exist at this time, but any attempt to dereference them will result in a panic. Once the unowned reference count reaches 0 (which may be immediately if there are no unowned references to the object), the object's memory is freed and it becomes `DEAD`.

Based on this implementation, we can see that unowned references have relatively similar performance overhead to strong references. Each assignment and deassignment requires updating a reference count, and then we have some extra logic when either reference count hits zero. However, unowned reference have a major issue in terms of memory. If we create some large object A and then remove all of the strong references to it but keep an unowned reference around, all the space we allocated for the object must still exist.

Weak references solve this issue through a structure called the side table. An object's side table entry is allocated seperately from the main object, and contains all three reference counts (strong, weak, and unowned) as well as the state. The side table and main object also contain mutual pointers to each other. Unlike strong and unowned references which point directly to the object, weak references are internally pointers to the side table.

#figure(
  cetz.canvas(
    length: 0.75cm, {
    import cetz.draw: *

    set-style(mark: (start: none, end: ">"))

    // just strong ref
    group({
      let x = 0
      let y = 0
      rect((x,y),(x + 8,y - 1), fill: gray, padding: 0.2, name: "header")
      content("header.center", `Heap Object`)
      rect((x, y - 1),(x + 8, y - 3), name: "body")
      content("body.north", `state = LIVE, SRC = 1, URC = 1`, anchor:"north", padding:(top:0.4, rest:0.2), name: "attr1")
      content("attr1.south", `...fields`, anchor:"north", padding:0.2, name: "attr2")

      content((x - 2.5, y - 1), "Strong Ref", padding: 0.2, name: "strongref")
      line("strongref.east", (x - 0.1, y - 1))
    })

    // strong and unowned
    group({
      let x = 0
      let y = -4
      rect((x,y),(x + 8,y - 1), fill: gray, padding: 0.2, name: "header")
      content("header.center", `Heap Object`)
      rect((x, y - 1),(x + 8, y - 3), name: "body")
      content("body.north", `state = LIVE, SRC = 1, URC = 2`, anchor:"north", padding:(top:0.4, rest:0.2), name: "attr1")
      content("attr1.south", `...fields`, anchor:"north", padding:0.2, name: "attr2")

      content((x - 2.5, y - 1), "Strong Ref", padding: 0.2, name: "strongref")
      content((x - 2.5, y - 2), "Unowned Ref", padding: 0.2, name: "unownedref")

      line("strongref.east", (x - 0.1, y - 1))
      line("unownedref.east", (x - 0.1, y - 2))
    })

    // strong, unowned and weak
    group({
      let x = 0
      let y = -8
      rect((x,y),(x + 4,y - 1), fill: gray, padding: 0.2, name: "header")
      content("header.center", `Heap Object`)
      rect((x, y - 1),(x + 4, y - 3), name: "body")
      content("body.north", `...fields`, anchor:"north", padding:(top:0.4, rest:0.2), name: "attr1")

      rect((x+6, y),(x + 14,y - 1), fill: gray, padding: 0.2, name: "sidetable_header")
      content("sidetable_header.center", `Side Table Entry`)
      rect((x+6, y - 1),(x + 14, y - 3), name: "sidetable_body")
      content("sidetable_body.north", `state = LIVE`, anchor:"north", padding:(top:0.4, rest:0.2), name: "sidetable_attr1")
      content("sidetable_attr1.south", `SRC = 1, URC = 2, WRC = 2`, anchor:"north", padding:(top:0.4, rest:0.2), name: "sidetable_attr2")

      content((x - 2.5, y - 1), "Strong Ref", padding: 0.2, name: "strongref")
      content((x - 2.5, y - 2), "Unowned Ref", padding: 0.2, name: "unownedref")
      content((x + 16.5, y - 1), "Weak Ref", padding: 0.2, name: "weakref")

      line("strongref.east", (x - 0.1, y - 1))
      line("unownedref.east", (x - 0.1, y - 2))
      line("weakref.west", (x + 14.1, y - 1))

      line((x + 4.2, y - 1), (x + 5.9, y - 1))
      line((x + 5.8, y - 2), (x + 4.1, y - 2))
    })

    // unowned and weak
    group({
      let x = 0
      let y = -12
      rect((x,y),(x + 4,y - 1), fill: gray, padding: 0.2, stroke:(dash:"dashed"),name: "header")
      content("header.center", `Heap Object`)
      rect((x, y - 1),(x + 4, y - 3), stroke:(dash:"dashed"), name: "body")
      content("body.north", `...fields`, anchor:"north", padding:(top:0.4, rest:0.2), name: "attr1")

      rect((x+6, y),(x + 14,y - 1), fill: gray, padding: 0.2, name: "sidetable_header")
      content("sidetable_header.center", `Side Table Entry`)
      rect((x+6, y - 1),(x + 14, y - 3), name: "sidetable_body")
      content("sidetable_body.north", `state = DEINITED`, anchor:"north", padding:(top:0.4, rest:0.2), name: "sidetable_attr1")
      content("sidetable_attr1.south", `SRC = 0, URC = 1, WRC = 2`, anchor:"north", padding:(top:0.4, rest:0.2), name: "sidetable_attr2")

      content((x - 2.5, y - 2), "Unowned Ref", padding: 0.2, name: "unownedref")
      content((x + 16.5, y - 1), "Weak Ref", padding: 0.2, name: "weakref")

      line("unownedref.east", (x - 0.1, y - 2))
      line("weakref.west", (x + 14.1, y - 1))

      line((x + 4.2, y - 1), (x + 5.9, y - 1))
      line((x + 5.8, y - 2), (x + 4.1, y - 2))
    })

    // weak
    group({
      let x = 0
      let y = -16

      rect((x+6, y),(x + 14,y - 1), fill: gray, padding: 0.2, name: "sidetable_header")
      content("sidetable_header.center", `Side Table Entry`)
      rect((x+6, y - 1),(x + 14, y - 3), name: "sidetable_body")
      content("sidetable_body.north", `state = FREED`, anchor:"north", padding:(top:0.4, rest:0.2), name: "sidetable_attr1")
      content("sidetable_attr1.south", `SRC = 0, URC = 0, WRC = 1`, anchor:"north", padding:(top:0.4, rest:0.2), name: "sidetable_attr2")

      content((x + 16.5, y - 1), "Weak Ref", padding: 0.2, name: "weakref")

      line("weakref.west", (x + 14.1, y - 1))
    })

    // line("attr2_b", "header_a.east", stroke: (dash: "dashed"))
  }),
  gap: 2em,
  caption: [An object following the side table lifecycle]
)<lifecycle_example>

Initially, objects start with no side table, and only gain one when a weak reference is created. This corresponds to the bottom path of the object life cycle shown in @object_state_machine. While very similar to the top path, there are a few key differences. First, all reference counts are moved into the side table. Next, the object gains a weak reference count. Similar to the unowned reference count, this starts out as $1+$ the real number of weak references.

On the "with side table" path, when a `DEINITED` object's unowned reference count drops to 0, it moves to a new state: `FREED`. In this transition, the original object's memory is freed--leaving only the side table entry--and the weak reference count is decremented to come in line with the real number of weak references. In the `FREED` state, only weak references to the object should remain, meaning all pointers to the original object's memory location should have been dropped. When a weak reference is checked, swift only need check the side table's state before returning either a `nil` value or a strong reference.

Finally, when the weak reference count drops to 0, the side table entry is deallocated, and the object can move to `DEAD`.

Above, @lifecycle_example shows the progression of an object gaining a strong, unowned, then weak reference and then losing them again in that order.

= Performance
Based on the implementation described above, we can see that there are some performance tradeoffs for using strong references. For example, the first weak reference to an must allocate a second segment of heap memory, which takes significant time. To test this I wrote three benchmarks to test reference creation, deinitialization and dereference, as described in @benchmark_code.

#figure(
  grid(
    columns: 2,
    column-gutter: 10em,
    row-gutter: 2em,
    [Classes (strong ref)], [Create],
    ```swift
class A{}
class B{
    var ref: A
    init(a: A){
        self.ref = a
    }
}
    ```,
    ```swift
let a = A()
for _ in 0..<count {
    let _ = B(a: a)
}
    ```,
    [Deref], [Destroy],
    ```swift
let a = A()
let b = B(a: a)
for _ in 0..<count {
    let _ = b.ref
}
    ```,
    ```swift
var b: B
for _ in 0..<count {
    let a = A()
    b = B(a: a)
}
    ```,
  ),
  gap: 2em,
  caption: [Benchmarking code]
)<benchmark_code>

#figure(
  grid(
    columns: 4,
    gutter: 2em,
    [Create], [Deref], [Destroy], [Destroy - Create],
    image("figures/create.png", width: 10em), image("figures/deref.png", width: 10em),
    image("figures/destroy.png", width: 10em), image("figures/destroy_minus_create.png", width: 10em),
  ),
  gap: 2em,
  caption: [Benchmarking performance results]
)<benchmark_results>

Each benchmark was run with `B.ref` set to all four reference types, run simultaneously to control for external factors affecting performance. The results for $N = 1,000,000,000$ are described in @benchmark_results. For the "Destroy" test, I specifically wanted to test the performance of moving from the `LIVE` state through the state machine to `DEAD`. Since testing this neccisarily also involved creating a reference, I also plotted the difference of the destroy and create tests to see if the performance difference could be accounted for by the creation time involved.

These times reflect what we expect from the implementation. Creating a strong, unowned, or unsafe reference take the same amount of time since they behave very similarly. Creating a weak reference allocates the side table entry, so it takes significantly longer. Similary for Destroy, the strong, unowned, and unsafe cases all are moving through the `DEINITING`, `DEINITED` and `DEAD` states, albeit at different points in execution, so we expect them to all take a similar amount of time. Weak references must move move through the `FREED` state and also deallocate the side table, so they take more time, even when the extra creation time is factored out.

The most surprising result to me personally is that the dereference time is similar across all reference types. I would expect that weak references would be slightly slower since they need to load the side table and then load the actual object based on the side table entry's pointer. However, what the benchmarking shows is that they are the slowest, but by a nearly undetectable amount.

= Process
At the start of this project, I had some prior experience with Swift, but hadn't fully explored the language. I chose Swift because it was a language that was created with mobile development in mind and I wanted to see how that affected the design of the runtime.

In my first week of research (week 5 of the quarter) I had a few goals: re-learn swift as a language, and find out where I could find information on the Swift runtime. I followed A Swift Tour#footnote("https://docs.swift.org/swift-book/documentation/the-swift-programming-language/guidedtour/") and started learning about the compilation pipeline. During this time I also found a very informative blog post by Jacob's Tech Tavern#footnote("https://blog.jacobstechtavern.com/p/the-swift-runtime-your-silent-partner") about how memory operations turned into runtime calls. Both the compilation pipline and the blog post referenced SIL, so for the tail end of this week I started reading the SIL documentation.

I underestimated how dense the SIL documentation would be, so for the entirety of week 6, I was just learning SIL. At the start of week 7, I just skimmed the last part of the documentation I hadn't finished, and returned to the blog post. The post itself is quite short, but it references lots of different parts of the `swift` repository, so I spent rest of week 7 following those links and getting a feel for how the repo is structured. Also during this time I started looking into how swift compiled for different platforms to try and find information on mobile-specific considerations or optimizations. What I found was that platform specifications were handled via a lot of compile-time macros and therefore were quite hard to understand. In addition, the constants used to activate these macros didn't have great documentation on how they were set, so finding exactly which code ran on IOS vs OSX was even more opaque.

Week 8 was a very productive week and also the week where my focus changed to weak references. I first read the Swift's Automatic Reference Counting documentation#footnote("https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/") at the start of this week, and seriously misunderstood how the different reference types worked. After doing some of my own testing, I corrected most of my initial misunderstandings, but also started wondering about the performance implications of these references. Using what I had learned from my SIL research and the process outlined in the Jacob's Tech Tavern article, I began to trace a number of unowned reference operations. Again I ran into issues with C++ macros, specifically that certain function names were defined via macro. For example, when I looked for where `visitLoadUnownedInst` was defined, I couldn't find anything because it was defined as `visitLoad##Name##Inst` in the `NEVER_LOADABLE_CHECKED_REF_STORAGE` macro.

Week 9 was a continuation of the previous weeks work, finally getting all the way down into the Swift runtime after chasing function calls for a while. All of my calls seemed to be ending in `HeapObject` calls, but my lack of experience with C++ headers got me a bit turned around as to where exactly the `HeapObject` calls were implemented.

At the beginning of week 10 I wanted to have some solid results for the in-class presentation, so I switched my focus to creating the benchmarks. They were relatively straightforward, but took some time to tune and mitigate interference from other processes on my computer. After creating and giving the presentation, I returned to the source code investigation with fresh eyes and almost immediately found the relevant portions of `HeapObject.h` and `RefCount.h`. Between these two files I was able to fully construct the reference counting model presented in this report.

= Future Work

With more time, there are a few directions I would take this project. The first is understanding the SIL mandatory transformations related to reference counting. A few of the sources I looked at mentioned these transformations, but I didn't have time to see what exactly they changed or were optimizing for. Next is that I want to create more realistic benchmarks for these reference types. For example, implementing a doubly linked list with each reference type on back edges and measuring the performance of push/pop/search operations and profiling the memory usage at various points during the program. In general, I didn't have as many concrete results on the memory tradeoffs of each reference as I would have liked. Finally I could look into the implementations of other languages which have weak references or pointers. Both Rust and C++ have special smart pointer types which implement reference counting and in turn have weak variations. Notably, I haven't found another language which has the unowned/weak seperation, and so comparing other language's implementations may give some insight into why Swift differentiates them.
