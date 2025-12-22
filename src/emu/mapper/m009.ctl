use ctlness::emu::cart::*;

pub struct Mmc2 {
    cart: Cart,
    mirroring: Mirroring,
    prg_bank: uint = 0,
    chr_banks: [uint; 4] = [0; 4],
    latch: [bool; 2] = [true; 2],

    pub fn new(cart: Cart): This => Mmc2(mirroring: cart.mirroring, cart:);

    impl super::Mapper {
        fn read_chr(mut this, addr: u16): u8 {
            let val = this.peek_chr(addr);
            if addr is 0x0fd8 | 0x0fe8 | 0x1fd8..=0x1fdf | 0x1fe8..=0x1fef {
                this.latch[addr >> 12] = (addr >> 4) & 0xff == 0xfe;
            }

            val
        }

        fn peek_chr(this, addr: u16): u8 {
            let range = addr >> 12;
            let bank = this.chr_banks[range * 2 + this.latch[range] as u16];
            this.cart.chr_rom[bank..][addr - range * 0x1000]
        }

        fn write_chr(mut this, _addr: u16, _val: u8) { }

        fn read_prg(this, addr: u16): u8 {
            if addr < 0xa000 {
                this.cart.prg_rom[this.prg_bank..][addr - 0x8000]
            } else {
                this.cart.prg_rom[this.cart.prg_rom.len() - 0x2000 * 3..][addr - 0xa000]
            }
        }

        fn write_prg(mut this, addr: u16, val: u8) {
            match addr {
                0xa000..=0xafff => this.prg_bank = (val & 0xf) as uint * 0x2000,
                0xb000..=0xefff => {
                    this.chr_banks[(addr - 0xb000) >> 12] = (val & 0x1f) as uint * 0x1000;
                }
                0xf000..=0xffff => {
                    this.mirroring = val & 1 == 0 then :Vertical else :Horizontal;
                }
                _ => {}
            }
        }

        fn mirroring(this): Mirroring => this.mirroring;

        fn reset(mut this) {
            *this = Mmc2::new(this.cart);
        }
    }
}
