import Foundation
class Parent: NSObject {let identifier=NSObject()}
class Fixture: Parent {let layer=NSObject();let numeric=17}
class OptionalFixture: NSObject {let layer:NSObject?=NSObject()}
class EmptyFixture:NSObject {let layer:NSObject?=nil}
class ScalarFixture:NSObject {let layer=23}
class SwiftReference {}
class SwiftFixture:NSObject {let layer=SwiftReference()}
func reference(_ object:NSObject,_ name:String)->AnyObject? {
 name.withCString { key in
  guard let pointer=copyScriptingReference(Unmanaged.passUnretained(object).toOpaque(),key) else{return nil}
  return Unmanaged<AnyObject>.fromOpaque(pointer).takeRetainedValue()
 }
}
@main struct Verify {
 static func main(){
  let object=Fixture(),optional=OptionalFixture()
  precondition(reference(object,"layer")===object.layer)
  precondition(reference(object,"identifier")===object.identifier)
  precondition(reference(optional,"layer")===optional.layer)
  precondition(reference(EmptyFixture(),"layer")==nil)
  precondition(reference(ScalarFixture(),"layer")==nil)
  let pure=SwiftFixture();precondition(reference(pure,"layer")===pure.layer)
  precondition(reference(object,"missing")==nil && reference(object,"numeric")==nil)
  print("Swift reference reflection preserves identity for inherited and optional objects; nil, scalar and unknown fields rejected.")
 }
}
