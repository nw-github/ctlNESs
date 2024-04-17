pub trait Mapper {
    fn read_chr(mut this, addr: u16): u8 {
        this.peek_chr(addr)
    }
    fn peek_chr(this, addr: u16): u8;
    fn write_chr(mut this, addr: u16, val: u8);

    fn read_prg(this, addr: u16): u8;
    fn write_prg(mut this, addr: u16, val: u8);

    fn mirroring(this): super::cart::Mirroring;

    fn scanline(mut this) {}

    fn reset(mut this);
}
