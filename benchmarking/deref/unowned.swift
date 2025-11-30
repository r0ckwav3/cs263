import Foundation;

class A{}
class B{
    unowned var ref: A
    init(a: A){
        self.ref = a
    }
}


if let arg = CommandLine.arguments.dropFirst().first, let count = Int(arg) {
    let start = Date().timeIntervalSince1970
    let a = A()
    let b = B(a: a)
    for _ in 0..<count {
        let _ = b.ref
    }
    let end = Date().timeIntervalSince1970
    print("Benchmark", CommandLine.arguments.first! ,"took:", end - start, "seconds")
}else{
    print("usage:", CommandLine.arguments.first!, " <iterations>")
}
