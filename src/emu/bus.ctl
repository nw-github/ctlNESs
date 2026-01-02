pub trait Mem {
    fn peek(this, addr: u16): ?u8;
    fn read(mut this, addr: u16): ?u8 => this.peek(addr);
    fn write(mut this, bus: *mut Bus, addr: u16, val: u8);
}

pub trait Mapper: Mem {
    fn peek_chr(this, addr: u16): u8;
    fn read_chr(mut this, addr: u16): u8 => this.peek_chr(addr);
    fn write_chr(mut this, addr: u16, val: u8);

    fn mirroring(this): super::cart::Mirroring;

    fn scanline(mut this) {}

    fn reset(mut this);
}

pub struct Bus {
    components: [*dyn mut Mem],
    last_read: u8,

    pub fn new(components: [*dyn mut Mem]): This => Bus(components:, last_read: 0);

    pub fn peek(this, addr: u16): u8 {
        mut result: ?u8 = null;
        for component in this.components.iter() {
            if component.peek(addr) is ?value {
                *result.get_or_insert(value) &= value;
            }
        }
        result ?? this.last_read
    }

    pub fn read(mut this, addr: u16): u8 {
        mut result: ?u8 = null;
        for component in this.components.iter_mut() {
            if component.read(addr) is ?value {
                *result.get_or_insert(value) &= value;
            }
        }

        if result.is_null() {
            eprintln("attempt to read from open bus at ${addr:X} => {this.last_read:X}");
        }

        this.last_read = result ?? this.last_read;
        this.last_read
    }

    pub fn write(mut this, addr: u16, val: u8) {
        for component in this.components.iter_mut() {
            component.write(this, addr, val);
        }
    }

    pub fn read_u16(mut this, addr: u16): u16 {
        (this.read(addr.wrapping_add(1)) as u16 << 8) | this.read(addr) as u16
    }

    pub fn read_u16_pw(mut this, addr: u16): u16 {
        let hi = (addr & 0xff00) + (addr.wrapping_add(1) & 0xff);
        (this.read(hi) as u16 << 8) | this.read(addr) as u16
    }

    pub fn peek_u16(this, addr: u16): u16 {
        (this.peek(addr.wrapping_add(1)) as u16 << 8) | this.peek(addr) as u16
    }
}

use std::range::Range;
use std::range::RangeInclusive;

pub struct Ram {
    pub buf: [mut u8..],
    pub range: RangeInclusive<u16>,

    pub fn at(size: uint, range: Range<u16>): This {
        This::at_inclusive(size, range.start..=range.end.checked_sub(1).unwrap_or(0))
    }

    pub fn at_inclusive(size: uint, range: RangeInclusive<u16>): This {
        Ram(buf: @[0u8; size][..], range:)
    }

    impl Mem {
        fn peek(this, addr: u16): ?u8 {
            if this.range.contains(&addr) {
                this.buf[(addr - this.range.start) as uint % this.buf.len()]
            }
        }

        fn write(mut this, _: *mut Bus, addr: u16, val: u8) {
            if this.range.contains(&addr) {
                this.buf[(addr - this.range.start) as uint % this.buf.len()] = val;
            }
        }
    }
}
