// Final project turn-ins due as a PDF submitted via this Assignment by 11:59pm Dec 9

// The PDF should include

//     Link to 10-15 minute video overviewing and demo-ing project (all members must participate; multiple videos (e.g. demo separated out) are fine for turnin)
//     Link to Google Sheets slides from video/demos
//     Steps for building/deploying project if you did an implementation
//     Link to 5 page writeup (PDF) on problem, solution, and findings Single space, single column, 1 inch margins -- images and references don't count toward page length.  You can go over the 5 page limit if needed.
//     Link to GitHub repo (shared with instructor)

#set page(
  "us-letter",
  margin: 1in
)

#show link: (body) => text(blue, underline(body))

#align(center)[
  #set text(weight: "bold", size: 14pt)
  On the Implementation and Performance of Swift's Weak References \
  #set text(weight: "bold", size: 10pt)
  Wren Vandervelde \
  CMPSC 263 F25
]

== Links:
- #link("https://youtu.be/EvbM6iRmsD8")[Video Link]
- #link("https://docs.google.com/presentation/d/1T4qcJu-7L01LAKorh8rdQBKxo0x31HyY-KH0odkfUnI/edit?usp=sharing")[Slides Link]
- #link("https://drive.google.com/file/d/1o6hCNAgmqU8tmIJpITU8Pn-B6oE966rH/view?usp=sharing")[Writeup Link]
- #link("https://github.com/r0ckwav3/cs263")[Github Repo]

== Build Instructions:
=== Benchmarks
To run the benchmarks, install #link("https://www.swift.org/install/")[Swift] and then run the `runtests_[name].sh` scripts from the `benchmarking` folder.

=== SIL Generation
To generate the SIL and LLVM IR code for the `tests` directory, use the commands:

```bash
swiftc -emit-sil -O main.swift -o sil.txt
swiftc -emit-irgen -O main.swift -o llvmir_unoptimized.txt
swiftc -emit-ir -O main.swift -o llvmir.txt
```
=== Refcount Debugging
To run `tests/unsafe_refcount` in debug mode use ```bash swift run --debugger``` and then in lldb use the command `(lldb) language swift refcount a!` to check the internal reference counts for an object.
