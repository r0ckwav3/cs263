// The Swift Programming Language
// https://docs.swift.org/swift-book

@main
struct unsafe_refcount {
  static func main() {
    var a: A? = A()
    var b: B? = B(a: a!)
    var c: C? = C(a: a!)
    a = nil
    b = nil
    c = nil
  }
}

class A {
  deinit {
    print("deiniting A")
  }
}

class B {
  unowned(unsafe) var a: A

  init(a: A) {
    self.a = a
  }

  deinit {
    print("deiniting B")
  }
}

class C {
  unowned var a: A

  init(a: A) {
    self.a = a
  }

  deinit {
    print("deiniting C")
  }
}
