use std::sync::Atomic;

pub struct RingBuffer<T> {
    buf: *raw T,
    cap: uint,
    read: Atomic<uint>,
    write: Atomic<uint>,

    pub fn new(size: uint): This {
        if size == 0 {
            panic("RingBuffer size must be non-zero");
        }

        RingBuffer(
            buf: Vec::<T>::with_capacity(size + 1).as_raw(),
            cap: size + 1,
            read: Atomic::new(0),
            write: Atomic::new(0),
        )
    }

    pub fn push(mut this, item: T): ?T {
        let pos = this.write.load();
        let next = (pos + 1) % this.cap;
        if next == this.read.load() {
            return item;
        }

        unsafe *(this.buf + pos) = item;
        this.write.store(next);
        null
    }

    pub fn pop(mut this): ?T {
        let pos = this.read.load();
        if pos != this.write.load() {
            this.read.store((pos + 1) % this.cap);
            unsafe *(this.buf + pos)
        }
    }

    pub fn len(this): uint {
        (2 * this.cap + this.write.load() - this.read.load()) % (2 * this.cap)
    }

    pub fn cap(this): uint {
        this.cap
    }
}
