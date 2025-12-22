use ctlness::emu::cart::*;

pub struct UxRom {
    cart: Cart,
    bank: u8 = 0,
    chr_ram: ?[u8; 0x2000],

    pub fn new(cart: Cart): This {
        UxRom(cart:, chr_ram: if cart.chr_rom.is_empty() { [0; 0x2000] })
    }

    impl super::Mapper {
        fn peek_chr(this, addr: u16): u8 {
            if &this.chr_ram is ?chr_ram {
                chr_ram[addr]
            } else {
                this.cart.chr_rom[addr]
            }
        }

        fn write_chr(mut this, addr: u16, val: u8) {
            if &mut this.chr_ram is ?chr_ram {
                chr_ram[addr] = val;
            }
        }

        fn read_prg(this, addr: u16): u8 {
            if addr < 0xc000 {
                this.cart.prg_rom[this.bank as uint * 0x4000..][addr & 0x3fff]
            } else {
                this.cart.prg_rom[this.cart.prg_rom.len() - 0x4000..][addr & 0x3fff]
            }
        }

        fn write_prg(mut this, _addr: u16, val: u8) {
            this.bank = val & 0xf;
        }

        fn mirroring(this): Mirroring => this.cart.mirroring;

        fn reset(mut this) {
            this.bank = 0;
        }
    }
}
