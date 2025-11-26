use ctlness::emu::cart::*;

packed struct Control {
    chr_mode: u1 = 0,
    prg_mode: u2 = 0b10,
    mirroring: u2 = 0b01,

    pub fn from_u8(val: u8): This {
        unsafe std::mem::transmute(val)
    }
}

pub struct Mmc1 {
    cart: Cart,
    chr_ram: ?[u8; 0x2000],

    write: u8 = 0,
    d0: u8 = 0,
    ctrl: Control = Control(),
    prg: u8 = 0,
    chr0: u8 = 0,
    chr1: u8 = 0,

    chr_bank0: uint = 0,
    chr_bank1: uint = 0,
    prg_bank0: uint = 0,
    prg_bank1: uint = 0,

    pub fn new(cart: Cart): This {
        Mmc1(
            chr_ram: if cart.chr_rom.is_empty() { [0u8; 0x2000] },
            prg_bank1: cart.prg_rom.len() - 0x4000,
            cart:
        )
    }

    fn update_prg_banks(mut this) {
        match this.ctrl.prg_mode {
            0..=1 => {
                this.prg_bank0 = 0x4000 * (this.prg & !1) as uint;
                this.prg_bank1 = this.prg_bank0 + 0x4000;
            }
            2 => {
                this.prg_bank0 = 0;
                this.prg_bank1 = 0x4000 * this.prg as uint;
            }
            3 => {
                this.prg_bank0 = 0x4000 * this.prg as uint;
                this.prg_bank1 = this.cart.prg_rom.len() - 0x4000;
            }
        }
    }

    impl super::Mapper {
        fn peek_chr(this, addr: u16): u8 {
            if &this.chr_ram is ?chr_ram {
                chr_ram[addr]
            } else if addr < 0x1000 {
                this.cart.chr_rom[this.chr_bank0..][addr]
            } else {
                this.cart.chr_rom[this.chr_bank1..][addr & 0xfff]
            }
        }

        fn write_chr(mut this, addr: u16, val: u8) {
            if &mut this.chr_ram is ?chr_ram {
                chr_ram[addr] = val;
            }
        }

        fn read_prg(this, addr: u16): u8 {
            let bank = addr < 0xc000 then this.prg_bank0 else this.prg_bank1;
            this.cart.prg_rom[bank..][addr & 0x3fff]
        }

        fn write_prg(mut this, addr: u16, val: u8) {
            guard val & (1 << 7) == 0 else {
                this.d0 = 0;
                this.write = 0;
                this.ctrl = Control();
                return this.update_prg_banks();
            }

            this.d0 = (this.d0 >> 1) | ((val & 1) << 4);
            guard ++this.write == 5 else {
                return;
            }

            match addr {
                ..=0x9fff => {
                    this.ctrl = Control::from_u8(this.d0);
                    this.update_prg_banks();

                    if this.ctrl.chr_mode == 0 {
                        this.chr_bank0 = 0x1000 * (this.chr0 | 1) as uint;
                        this.chr_bank1 = this.chr_bank0 + 0x1000;
                    } else {
                        this.chr_bank0 = 0x1000 * this.chr0 as uint;
                        this.chr_bank1 = 0x1000 * this.chr1 as uint;
                    }
                }
                ..=0xbfff => {
                    this.chr0 = this.d0;
                    if this.ctrl.chr_mode == 0 {
                        this.chr_bank0 = 0x1000 * (this.chr0 & 0x1e) as uint;
                        this.chr_bank1 = this.chr_bank0 + 0x1000;
                    } else {
                        this.chr_bank0 = 0x1000 * this.chr0 as uint;
                    }
                }
                ..=0xdfff => {
                    this.chr1 = this.d0;
                    if this.ctrl.chr_mode == 1 {
                        this.chr_bank1 = 0x1000 * this.chr1 as uint;
                    }
                }
                _ => {
                    this.prg = this.d0 & 0xf;
                    this.update_prg_banks();
                }
            }

            this.d0 = 0;
            this.write = 0;
        }

        fn mirroring(this): Mirroring {
            match this.ctrl.mirroring {
                0 => :OneScreenA,
                1 => :OneScreenB,
                2 => :Vertical,
                3 => :Horizontal,
            }
        }

        fn reset(mut this) {
            *this = Mmc1::new(this.cart);
        }
    }
}
