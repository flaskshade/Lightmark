import SwiftUI
let path = RoundedRectangle(cornerRadius: 16, style: .continuous).path(in: CGRect(x: 0, y: 0, width: 660, height: 650))
path.cgPath.applyWithBlock { pointer in
 let e = pointer.pointee
 switch e.type {
 case .moveToPoint: print("M", e.points[0])
 case .addLineToPoint: print("L", e.points[0])
 case .addQuadCurveToPoint: print("Q", e.points[0], e.points[1])
 case .addCurveToPoint: print("C", e.points[0], e.points[1], e.points[2])
 case .closeSubpath: print("Z")
 @unknown default: break
 }
}
