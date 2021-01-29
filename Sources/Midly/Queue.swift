import CoreMedia

struct Queue<T: AnyObject> {
    fileprivate let queue: CMSimpleQueue
    
    init(capacity: Int) throws {
        queue = try CMSimpleQueue(capacity: capacity)
    }
    
    func purge(limit: Int = 0) {
        repeat {
            if queue.count <= limit {
                break
            }
            let ptr = queue.dequeue()
            if let ptr = ptr {
                Unmanaged<T>.fromOpaque(ptr).release()
            }
            else {
                break
            }
        }
        while true
    }
    
    func dequeue() -> T? {
        guard let item = queue.dequeue() else {
            return nil
        }
        
        return Unmanaged<AnyObject>.fromOpaque(item)
            .autorelease()
            .takeUnretainedValue() as? T
    }
    
    func enqueue(_ item: T) throws {
        
    }
    
    var head: T? {
        guard let item = queue.head else {
            return nil
        }
        
        return Unmanaged<AnyObject>.fromOpaque(item)
            .autorelease()
            .takeUnretainedValue() as? T
    }
}
