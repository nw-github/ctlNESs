use ctlness::emu::cart::*;

packed struct Control {
    target_reg: u3 = 0,
    unused: u3 = 0,
    prg_inversion: bool = false,
    chr_inversion: bool = false,

    pub fn from_u8(val: u8): This {
        unsafe std::mem::transmute(val)
    }
}

pub struct Mmc3 {
    cart: Cart,
    irq_pending: *mut bool,

    ctrl: Control = Control(),
    bank_regs: [u8; 8] = [0; 8],

    irq_enabled: bool = false,
    irq_counter: u8 = 0,
    irq_latch: u8 = 0,
    irq_reload_pending: bool = false,

    mirroring_ram: [u8; 0x1000] = [0; 0x1000],
    prg_banks: [uint; 4],
    chr_banks: [uint; 8],

    mirroring: Mirroring = :Horizontal,

    pub fn new(cart: Cart, irq_pending: *mut bool): This {
        mut chr_banks = [cart.chr_rom.len() - 0x400; 8];
        chr_banks[0] = cart.chr_rom.len() - 0x800;
        chr_banks[3] = cart.chr_rom.len() - 0x800;
        Mmc3(
            cart:,
            irq_pending:,
            prg_banks: [
                cart.prg_rom.len() - 0x4000,
                cart.prg_rom.len() - 0x2000,
                cart.prg_rom.len() - 0x4000,
                cart.prg_rom.len() - 0x2000,
            ],
            chr_banks:,
        )
    }

    impl super::Mapper {
        fn peek_chr(this, addr: u16): u8 {
            match addr {
                ..0x1fff => this.cart.chr_rom[this.chr_banks[addr >> 10] + (addr & 0x3ff) as uint],
                ..=0x2fff => this.mirroring_ram[addr - 0x2000],
                _ => 0,
            }
        }

        fn write_chr(mut this, addr: u16, val: u8) {
            if addr is 0x2000..=0x2fff {
                this.mirroring_ram[addr - 0x2000] = val;
            }
        }

        fn read_prg(this, addr: u16): u8 {
            let bank = match addr {
                ..=0x9fff => 0,
                ..=0xbfff => 1,
                ..=0xdfff => 2,
                _ => 3,
            };
            this.cart.prg_rom[this.prg_banks[bank]..][addr & 0x1fff]
        }

        fn write_prg(mut this, addr: u16, val: u8) {
            match addr {
                ..=0x9fff => {
                    guard addr & 1 != 0 else {
                        this.ctrl = Control::from_u8(val);
                        return;
                    }

                    this.bank_regs[this.ctrl.target_reg] = val;
                    this.chr_banks = [
                        (this.bank_regs[0] & 0xfe) as uint * 0x400,
                        ((this.bank_regs[0] & 0xfe) + 1) as uint * 0x400,
                        (this.bank_regs[1] & 0xfe) as uint * 0x400,
                        ((this.bank_regs[1] & 0xfe) + 1) as uint * 0x400,
                        this.bank_regs[2] as uint * 0x400,
                        this.bank_regs[3] as uint * 0x400,
                        this.bank_regs[4] as uint * 0x400,
                        this.bank_regs[5] as uint * 0x400,
                    ];
                    if this.ctrl.chr_inversion {
                        std::mem::swap(&mut this.chr_banks[0], &mut this.chr_banks[4]);
                        std::mem::swap(&mut this.chr_banks[1], &mut this.chr_banks[5]);
                        std::mem::swap(&mut this.chr_banks[2], &mut this.chr_banks[6]);
                        std::mem::swap(&mut this.chr_banks[3], &mut this.chr_banks[7]);
                    }
                    this.prg_banks = [
                        (this.bank_regs[6] & 0x3f) as uint * 0x2000,
                        (this.bank_regs[7] & 0x3f) as uint * 0x2000,
                        this.cart.prg_rom.len() - 0x4000,
                        this.cart.prg_rom.len() - 0x2000,
                    ];
                    if this.ctrl.prg_inversion {
                        std::mem::swap(&mut this.prg_banks[0], &mut this.prg_banks[2]);
                    }
                },
                ..=0xbfff => {
                    guard addr & 0x1 == 0 else {
                        // PRG_RAM protect
                        return;
                    }

                    this.mirroring = if this.cart.mirroring is :FourScreen {
                        :FourScreen
                    } else if val & 0x1 != 0 {
                        :Horizontal
                    } else {
                        :Vertical
                    };
                },
                ..=0xdfff => {
                    if addr & 1 == 0 {
                        this.irq_latch = val;
                    } else {
                        this.irq_counter = 0;
                        this.irq_reload_pending = true;
                    }
                },
                _ => {
                    // Writing any value to this register will disable MMC3 interrupts AND
                    // acknowledge any pending interrupts.
                    this.irq_enabled = addr & 1 != 0;
                }
            }
        }

        fn mirroring(this): Mirroring {
            this.mirroring
        }

        fn scanline(mut this) {
            if this.irq_counter == 0 or this.irq_reload_pending {
                this.irq_counter = this.irq_latch;
                this.irq_reload_pending = false;
            } else if --this.irq_counter == 0 and this.irq_enabled {
                *this.irq_pending = true;
            }
        }

        fn reset(mut this) {
            this.ctrl = Control();
            this.bank_regs = [0; 8];
            this.irq_enabled = false;
            this.irq_counter = 0;
            this.irq_latch = 0;
            this.irq_reload_pending = false;
            this.prg_banks = [0; 4];
            this.chr_banks = [0; 8];
            this.mirroring = :Horizontal;
        }
    }
}
