pub extension ReadExt for [u8..] {
    pub fn read_exact(mut this, n: uint): ?[u8..] {
        if this.len() >= n {
            let result = this[..n];
            *this = this[n..];
            result
        }
    }

    pub fn read_u8(mut this): ?u8 {
        if this is [byte, ...rest] {
            *this = rest;
            *byte
        }
    }

    pub fn read_u16_be(mut this): ?u16 {
        if this is [hi, lo, ...rest] {
            *this = rest;
            (*hi as u16 << 8) | (*lo as u16)
        }
    }

    pub fn read_u16_le(mut this): ?u16 {
        if this is [lo, hi, ...rest] {
            *this = rest;
            (*hi as u16 << 8) | (*lo as u16)
        }
    }
}

mod __libc {
    use super::File;

    pub extern fn fopen(path: *c_char, mode: *c_char): ?*mut File;
    pub extern fn fseek(stream: *mut File, offset: c_long, whence: c_int): c_int;
    pub extern fn fread(ptr: *mut c_void, size: uint, nmemb: uint, stream: *mut File): uint;
    pub extern fn fwrite(ptr: *c_void, size: uint, nmemb: uint, stream: *mut File): uint;
    pub extern fn ftell(stream: *mut File): c_long;
    pub extern fn fclose(stream: *mut File): c_int;
}

pub union SeekPos {
    shared offset: uint,

    Start,
    Current,
    End,
}

@(opaque, c_name(FILE))
pub struct File {
    pub fn open(path: str, mode: str): ?*mut File {
        unsafe __libc::fopen(path.as_raw() as *c_char, mode.as_raw() as *c_char)
    }

    pub fn seek(mut this, pos: SeekPos): c_int {
        unsafe __libc::fseek(this, pos.offset as! c_long, match pos {
            SeekPos::Start => 0,
            SeekPos::Current => 1,
            SeekPos::End => 2,
        })
    }

    pub fn read(mut this, buf: [mut u8..]): uint {
        unsafe __libc::fread(
            buf.as_raw() as *mut c_void,
            core::mem::size_of::<u8>(),
            buf.len(),
            this,
        )
    }

    pub fn write(mut this, buf: [u8..]): uint {
        unsafe __libc::fwrite(buf.as_raw() as *c_void, 1, buf.len(), this)
    }

    pub fn tell(mut this): c_long {
        unsafe __libc::ftell(this)
    }

    pub fn close(mut this): c_int {
        unsafe __libc::fclose(this)
    }
}
