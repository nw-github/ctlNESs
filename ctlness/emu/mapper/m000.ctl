use ctlness::emu::cart::*;

pub struct Nrom {
    cart: Cartridge,
    one_bank: bool,
    chr_ram: ?[u8; 0x2000],

    pub fn new(cart: Cartridge): This {
        Nrom(
            one_bank: cart.prg_rom.len() == 0x4000,
            chr_ram: if cart.chr_rom.is_empty() { [0; 0x2000] },
            cart:
        )
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
            if this.one_bank {
                this.cart.prg_rom[(addr - 0x8000) & 0x3fff]
            } else {
                this.cart.prg_rom[addr - 0x8000]
            }
        }

        fn write_prg(mut this, addr: u16, val: u8) {
            eprintln("attempt to write 0x{
                val.to_str_radix(16)} to rom at addr 0x{
                addr.to_str_radix(16)}");
        }

        fn mirroring(this): Mirroring {
            this.cart.mirroring
        }

        fn reset(mut this) {}
    }
}
