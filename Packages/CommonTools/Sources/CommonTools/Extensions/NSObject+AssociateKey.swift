import Foundation
extension NSObject {
   public func associate<T>(key: UnsafeRawPointer, value: T, policy: objc_AssociationPolicy = .OBJC_ASSOCIATION_RETAIN_NONATOMIC) {
        objc_setAssociatedObject(self, key, value, policy)
    }

    public func associated<T>(key: UnsafeRawPointer, initializer: (() -> T)? = nil) -> T? {
        if let value = objc_getAssociatedObject(self, key) as? T {
            return value
        }

        if let initializer = initializer {
            let newValue = initializer()
            associate(key: key, value: newValue)

            return newValue
        }

        return nil
    }
}
