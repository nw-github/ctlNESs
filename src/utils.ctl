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

mod libc {
    use super::File;

    pub extern fn fopen(path: ^c_char, mode: ^c_char): ?*mut File;
    pub extern fn fseek(stream: *mut File, offset: c_long, whence: c_int): c_int;
    pub extern fn fread(ptr: ^mut void, size: uint, nmemb: uint, stream: *mut File): uint;
    pub extern fn fwrite(ptr: ^void, size: uint, nmemb: uint, stream: *mut File): uint;
    pub extern fn ftell(stream: *mut File): c_long;
    pub extern fn fclose(stream: *mut File): c_int;
}

pub union SeekPos {
    shared offset: i64,

    Start,
    Current,
    End,
}

@(c_opaque, c_name(FILE))
pub union File {
    pub fn open(kw path: str, kw mode: str): ?*mut File {
        unsafe libc::fopen(path.as_raw().cast(), mode.as_raw().cast())
    }

    pub fn seek(mut this, pos: SeekPos): c_int {
        unsafe libc::fseek(this, pos.offset as! c_long, match pos {
            SeekPos::Start => 0,
            SeekPos::Current => 1,
            SeekPos::End => 2,
        })
    }

    pub fn read(mut this, buf: [mut u8..]): uint {
        unsafe libc::fread(buf.as_raw_mut().cast(), std::mem::size_of::<u8>(), buf.len(), this)
    }

    pub fn write(mut this, buf: [u8..]): uint {
        unsafe libc::fwrite(buf.as_raw().cast(), 1, buf.len(), this)
    }

    pub fn tell(mut this): i64 => unsafe libc::ftell(this) as! i64;

    pub fn close(mut this): c_int => unsafe libc::fclose(this);
}
