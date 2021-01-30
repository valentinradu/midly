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
        
        return Unmanaged<T>.fromOpaque(item)
            .autorelease()
            .takeUnretainedValue()
    }
    
    func enqueue(_ item: T) throws {
        let ptr = Unmanaged<T>.passRetained(item)
        
        do {
            try queue.enqueue(ptr.toOpaque())
        }
        catch let error {
            ptr.release()
            throw error
        }
    }
    
    var head: T? {
        guard let item = queue.head else {
            return nil
        }
        
        return Unmanaged<T>.fromOpaque(item)
            .retain()
            .autorelease()
            .takeUnretainedValue()
    }
}
