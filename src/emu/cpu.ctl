use super::ppu::Ppu;
use super::apu::Apu;
use super::mapper::Mapper;
use super::Input;

pub union Load { Imm, Zp, Zpx, Zpy, Abs, Abx, Aby, Izx, Izy }
pub union Store { Zp, Zpx, Zpy, Abs, Abx, Aby, Izx, Izy }
pub union Operation { Or, And, Xor, Adc, Sbc }
pub union IncLoad { Zp, Zpx, Abs, Abx }
pub union Shift { Asl, Lsr, Rol, Ror }
pub union Reg { A, X, Y, P, S }
pub union Flag { Carry, Zero, IntDisable, Decimal, Break, Unused, Overflow, Negative }

packed struct Flags {
    carry: bool = false,
    zero: bool = false,
    int_disable: bool = false,
    decimal: bool = false,
    brk: bool = false,
    unused: bool = false,
    overflow: bool = false,
    negative: bool = false,

    @(inline(always))
    pub fn get(my this, bit: Flag): bool {
        (this.into_u8() >> bit as u8) & 1 != 0
    }

    @(inline(always))
    pub fn set(mut this, bit: Flag, val: bool) {
        if val {
            *this.as_u8_mut() |= (1 << bit as u8);
        } else {
            *this.as_u8_mut() &= !(1 << bit as u8);
        }
    }

    pub fn into_u8(my this): u8 {
        unsafe std::mem::transmute(this)
    }

    pub fn as_u8_mut(mut this): *mut u8 {
        unsafe this as *mut u8
    }

    pub fn set_zn(mut this, val: u8) {
        this.negative = val & 0x80 != 0;
        this.zero = val == 0;
    }

    impl std::fmt::Format {
        fn fmt(this, f: *mut std::fmt::Formatter) {
            f.write_str(this.negative then "N" else "-");
            f.write_str(this.overflow then "V" else "-");
            f.write_str(this.decimal then "D" else "-");
            f.write_str(this.int_disable then "I" else "-");
            f.write_str(this.zero then "Z" else "-");
            f.write_str(this.carry then "C" else "-");
        }
    }
}

union Interrupt { Irq, Nmi, Brk }

pub struct Cpu {
    a: u8 = 0,
    x: u8 = 0,
    y: u8 = 0,
    p: Flags = Flags(int_disable: true, brk: true, overflow: true),
    s: u8 = 0xfd,
    pc: u16,
    pub bus: CpuBus,

    odd_cycle: bool = false,
    cycles: u64 = 0,
    pub nmi_pending: bool = false,
    pub irq_pending: bool = false,

    pub fn new(mut bus: CpuBus): This {
        Cpu(pc: bus.read_u16(0xfffc), bus:)
    }

    pub fn step(mut this, dmc_stall: bool) {
        if dmc_stall {
            this.cycles += 4;
        }

        if this.bus.dma_flag {
            this.bus.dma_flag = false;
            this.cycles += 513 + this.odd_cycle as u64;
        }

        this.odd_cycle = !this.odd_cycle;
        if this.cycles-- > 1 {
            return;
        }

        this.cycles = 0;
        if this.nmi_pending or this.irq_pending {
            let typ = if this.nmi_pending { Interrupt::Nmi } else { Interrupt::Irq };
            this.nmi_pending = false;
            this.irq_pending = false;
            return this.interrupt(typ);
        }

        match this.read() {
            0x00 => this.brk(),
            0x01 => this.arithmetic(Load::Izx, Operation::Or),
            0x05 => this.arithmetic(Load::Zp, Operation::Or),
            0x06 => this.shift(IncLoad::Zp, Shift::Asl),
            0x08 => this.push_reg(Reg::P),
            0x09 => this.arithmetic(Load::Imm, Operation::Or),
            0x0a => this.shift(null, Shift::Asl),
            0x0d => this.arithmetic(Load::Abs, Operation::Or),
            0x0e => this.shift(IncLoad::Abs, Shift::Asl),
            0x10 => this.branch(Flag::Negative, false),
            0x11 => this.arithmetic(Load::Izy, Operation::Or),
            0x15 => this.arithmetic(Load::Zpx, Operation::Or),
            0x16 => this.shift(IncLoad::Zpx, Shift::Asl),
            0x18 => this.flag(Flag::Carry, false),
            0x19 => this.arithmetic(Load::Aby, Operation::Or),
            0x1d => this.arithmetic(Load::Abx, Operation::Or),
            0x1e => this.shift(IncLoad::Abx, Shift::Asl),
            0x20 => this.jsr(),
            0x21 => this.arithmetic(Load::Izx, Operation::And),
            0x24 => this.bit(zp: true),
            0x25 => this.arithmetic(Load::Zp, Operation::And),
            0x26 => this.shift(IncLoad::Zp, Shift::Rol),
            0x28 => this.pull(Reg::P),
            0x29 => this.arithmetic(Load::Imm, Operation::And),
            0x2a => this.shift(null, Shift::Rol),
            0x2c => this.bit(zp: false),
            0x2d => this.arithmetic(Load::Abs, Operation::And),
            0x2e => this.shift(IncLoad::Abs, Shift::Rol),
            0x30 => this.branch(Flag::Negative, true),
            0x31 => this.arithmetic(Load::Izy, Operation::And),
            0x35 => this.arithmetic(Load::Zpx, Operation::And),
            0x36 => this.shift(IncLoad::Zpx, Shift::Rol),
            0x38 => this.flag(Flag::Carry, true),
            0x39 => this.arithmetic(Load::Aby, Operation::And),
            0x3d => this.arithmetic(Load::Abx, Operation::And),
            0x3e => this.shift(IncLoad::Abx, Shift::Rol),
            0x40 => this.rti(),
            0x41 => this.arithmetic(Load::Izx, Operation::Xor),
            0x45 => this.arithmetic(Load::Zp, Operation::Xor),
            0x46 => this.shift(IncLoad::Zp, Shift::Lsr),
            0x4c => this.jmp(ind: false),
            0x48 => this.push_reg(Reg::A),
            0x49 => this.arithmetic(Load::Imm, Operation::Xor),
            0x4a => this.shift(null, Shift::Lsr),
            0x4d => this.arithmetic(Load::Abs, Operation::Xor),
            0x4e => this.shift(IncLoad::Abs, Shift::Lsr),
            0x50 => this.branch(Flag::Overflow, false),
            0x51 => this.arithmetic(Load::Izy, Operation::Xor),
            0x55 => this.arithmetic(Load::Zpx, Operation::Xor),
            0x56 => this.shift(IncLoad::Zpx, Shift::Lsr),
            0x58 => this.flag(Flag::IntDisable, false),
            0x59 => this.arithmetic(Load::Aby, Operation::Xor),
            0x5d => this.arithmetic(Load::Abx, Operation::Xor),
            0x5e => this.shift(IncLoad::Abx, Shift::Lsr),
            0x60 => this.rts(),
            0x61 => this.arithmetic(Load::Izx, Operation::Adc),
            0x65 => this.arithmetic(Load::Zp, Operation::Adc),
            0x66 => this.shift(IncLoad::Zp, Shift::Ror),
            0x68 => this.pull(Reg::A),
            0x69 => this.arithmetic(Load::Imm, Operation::Adc),
            0x6a => this.shift(null, Shift::Ror),
            0x6c => this.jmp(ind: true),
            0x6d => this.arithmetic(Load::Abs, Operation::Adc),
            0x6e => this.shift(IncLoad::Abs, Shift::Ror),
            0x70 => this.branch(Flag::Overflow, true),
            0x71 => this.arithmetic(Load::Izy, Operation::Adc),
            0x75 => this.arithmetic(Load::Zpx, Operation::Adc),
            0x76 => this.shift(IncLoad::Zpx, Shift::Ror),
            0x78 => this.flag(Flag::IntDisable, true),
            0x79 => this.arithmetic(Load::Aby, Operation::Adc),
            0x7d => this.arithmetic(Load::Abx, Operation::Adc),
            0x7e => this.shift(IncLoad::Abx, Shift::Ror),
            0x81 => this.store(Reg::A, Store::Izx),
            0x84 => this.store(Reg::Y, Store::Zp),
            0x85 => this.store(Reg::A, Store::Zp),
            0x86 => this.store(Reg::X, Store::Zp),
            0x88 => this.inc_dec_reg(dec: true, Reg::Y),
            0x8a => this.transfer(src: Reg::X, dst: Reg::A),
            0x8c => this.store(Reg::Y, Store::Abs),
            0x8d => this.store(Reg::A, Store::Abs),
            0x8e => this.store(Reg::X, Store::Abs),
            0x90 => this.branch(Flag::Carry, false),
            0x91 => this.store(Reg::A, Store::Izy),
            0x94 => this.store(Reg::Y, Store::Zpx),
            0x95 => this.store(Reg::A, Store::Zpx),
            0x96 => this.store(Reg::X, Store::Zpy),
            0x98 => this.transfer(src: Reg::Y, dst: Reg::A),
            0x99 => this.store(Reg::A, Store::Aby),
            0x9a => this.transfer(src: Reg::X, dst: Reg::S),
            0x9d => this.store(Reg::A, Store::Abx),
            0xa0 => this.load(Reg::Y, Load::Imm),
            0xa1 => this.load(Reg::A, Load::Izx),
            0xa2 => this.load(Reg::X, Load::Imm),
            0xa4 => this.load(Reg::Y, Load::Zp),
            0xa5 => this.load(Reg::A, Load::Zp),
            0xa6 => this.load(Reg::X, Load::Zp),
            0xa8 => this.transfer(src: Reg::A, dst: Reg::Y),
            0xa9 => this.load(Reg::A, Load::Imm),
            0xaa => this.transfer(src: Reg::A, dst: Reg::X),
            0xac => this.load(Reg::Y, Load::Abs),
            0xad => this.load(Reg::A, Load::Abs),
            0xae => this.load(Reg::X, Load::Abs),
            0xb0 => this.branch(Flag::Carry, true),
            0xb1 => this.load(Reg::A, Load::Izy),
            0xb4 => this.load(Reg::Y, Load::Zpx),
            0xb5 => this.load(Reg::A, Load::Zpx),
            0xb6 => this.load(Reg::X, Load::Zpy),
            0xb8 => this.flag(Flag::Overflow, false),
            0xb9 => this.load(Reg::A, Load::Aby),
            0xba => this.transfer(src: Reg::S, dst: Reg::X),
            0xbc => this.load(Reg::Y, Load::Abx),
            0xbd => this.load(Reg::A, Load::Abx),
            0xbe => this.load(Reg::X, Load::Aby),
            0xc0 => this.cmp(Reg::Y, Load::Imm),
            0xc1 => this.cmp(Reg::A, Load::Izx),
            0xc4 => this.cmp(Reg::Y, Load::Zp),
            0xc5 => this.cmp(Reg::A, Load::Zp),
            0xc6 => this.inc_dec(dec: true, IncLoad::Zp),
            0xc8 => this.inc_dec_reg(dec: false, Reg::Y),
            0xc9 => this.cmp(Reg::A, Load::Imm),
            0xca => this.inc_dec_reg(dec: true, Reg::X),
            0xcc => this.cmp(Reg::Y, Load::Abs),
            0xcd => this.cmp(Reg::A, Load::Abs),
            0xce => this.inc_dec(dec: true, IncLoad::Abs),
            0xd0 => this.branch(Flag::Zero, false),
            0xd1 => this.cmp(Reg::A, Load::Izy),
            0xd5 => this.cmp(Reg::A, Load::Zpx),
            0xd6 => this.inc_dec(dec: true, IncLoad::Zpx),
            0xd8 => this.flag(Flag::Decimal, false),
            0xd9 => this.cmp(Reg::A, Load::Aby),
            0xdd => this.cmp(Reg::A, Load::Abx),
            0xde => this.inc_dec(dec: true, IncLoad::Abx),
            0xe0 => this.cmp(Reg::X, Load::Imm),
            0xe1 => this.arithmetic(Load::Izx, Operation::Sbc),
            0xe4 => this.cmp(Reg::X, Load::Zp),
            0xe5 => this.arithmetic(Load::Zp, Operation::Sbc),
            0xe6 => this.inc_dec(dec: false, IncLoad::Zp),
            0xe8 => this.inc_dec_reg(dec: false, Reg::X),
            0xe9 => this.arithmetic(Load::Imm, Operation::Sbc),
            0xea => this.nop(),
            0xec => this.cmp(Reg::X, Load::Abs),
            0xed => this.arithmetic(Load::Abs, Operation::Sbc),
            0xee => this.inc_dec(dec: false, IncLoad::Abs),
            0xf0 => this.branch(Flag::Zero, true),
            0xf1 => this.arithmetic(Load::Izy, Operation::Sbc),
            0xf5 => this.arithmetic(Load::Zpx, Operation::Sbc),
            0xf6 => this.inc_dec(dec: false, IncLoad::Zpx),
            0xf8 => this.flag(Flag::Decimal, true),
            0xf9 => this.arithmetic(Load::Aby, Operation::Sbc),
            0xfd => this.arithmetic(Load::Abx, Operation::Sbc),
            0xfe => this.inc_dec(dec: false, IncLoad::Abx),
            op => eprintln("invalid opcode {op:#x}, reading at {this.pc.wrapping_sub(1):#x}"),
        }
    }

    pub fn reset(mut this) {
        this.pc = this.bus.read_u16(0xfffc);
        this.s -= 3;
        this.p.int_disable = true;
    }

    // ------------

    fn interrupt(mut this, typ: Interrupt) {
        guard !this.p.int_disable or typ is :Nmi else {
            return;
        }

        this.cycles += 6; // 7
        let vector = this.bus.read_u16(if typ is :Nmi { 0xfffa } else { 0xfffe });
        this.push_u16(this.pc);
        this.push_flags(interrupt: typ is :Nmi | :Irq);
        this.p.int_disable = true;
        this.pc = vector;
    }

    fn read(mut this): u8 {
        this.bus.read(this.pc++)
    }

    fn read_u16(mut this): u16 {
        let val = this.bus.read_u16(this.pc);
        this.pc += 2;
        val
    }

    fn push(mut this, src: u8) {
        this.bus.write(0x100 + this.s as u16, src);
        this.s--;
    }

    fn push_u16(mut this, src: u16) {
        this.push((src >> 8) as! u8);
        this.push((src & 0xff) as! u8);
    }

    fn push_flags(mut this, kw interrupt: bool) {
        mut p = this.p;
        p.brk = !interrupt;
        p.unused = true;
        this.push(p.into_u8());
    }

    fn pop(mut this): u8 {
        this.s++;
        this.bus.read(0x100 + this.s as u16)
    }

    fn pop_u16(mut this): u16 {
        this.pop() as u16 | (this.pop() as u16 << 8)
    }

    fn help_load(mut this, typ: Load): u8 {
        match typ {
            Load::Imm => {
                this.cycles += 2;
                this.read()
            }
            Load::Zp => {
                this.cycles += 3;
                this.bus.read(this.read() as u16)
            }
            Load::Zpx => {
                this.cycles += 4;
                this.bus.read(this.read().wrapping_add(this.x) as u16)
            }
            Load::Zpy => {
                this.cycles += 4;
                this.bus.read(this.read().wrapping_add(this.y) as u16)
            }
            Load::Abs => {
                this.cycles += 4;
                this.bus.read(this.read_u16())
            }
            Load::Abx => {
                this.cycles += 4;
                let addr = this.read_u16();
                let page = addr >> 8;
                let addr = addr.wrapping_add(this.x as u16);
                this.cycles += (page != addr >> 8) as u64;
                this.bus.read(addr)
            }
            Load::Aby => {
                this.cycles += 4;
                let addr = this.read_u16();
                let page = addr >> 8;
                let addr = addr.wrapping_add(this.y as u16);
                this.cycles += (page != addr >> 8) as u64;
                this.bus.read(addr)
            }
            Load::Izx => {
                this.cycles += 6;
                this.bus.read(this.bus.read_u16_pw(this.read().wrapping_add(this.x) as u16))
            }
            Load::Izy => {
                this.cycles += 5;
                let addr = this.bus.read_u16_pw(this.read() as u16);
                let page = addr >> 8;
                let addr = addr.wrapping_add(this.y as u16);
                this.cycles += (page != addr >> 8) as u64;
                this.bus.read(addr)
            }
        }
    }

    fn inc_load_addr(mut this, typ: IncLoad): (u16, u8) {
        let addr = match typ {
            IncLoad::Zp => {
                this.cycles += 5;
                this.read() as u16
            }
            IncLoad::Zpx => {
                this.cycles += 6;
                this.read().wrapping_add(this.x) as u16
            }
            IncLoad::Abs => {
                this.cycles += 6;
                this.read_u16()
            }
            IncLoad::Abx => {
                this.cycles += 7;
                this.read_u16().wrapping_add(this.x as u16)
            }
        };
        (addr, this.bus.read(addr))
    }

    fn add(mut this, lhs: u8, rhs: u8, kw carry: bool, kw overflow: bool): u8 {
        // decimal mode is disabled on the NES, so ignore it here

        let res = lhs as u16 + rhs as u16 + carry as u16;
        this.p.carry = res > 0xff;
        let res = (res & 0xff) as! u8;
        if overflow {
            this.p.overflow = (res ^ lhs) & (res ^ rhs) & (1 << 7) != 0;
        }
        res
    }

    fn register(mut this, reg: Reg): *mut u8 {
        match reg {
            Reg::A => &mut this.a,
            Reg::X => &mut this.x,
            Reg::Y => &mut this.y,
            Reg::S => &mut this.s,
            Reg::P => this.p.as_u8_mut(),
        }
    }

    // ------------

    // LDA LDX LDY
    fn load(mut this, reg: Reg, typ: Load) {
        let reg = this.register(reg);
        *reg = this.help_load(typ);
        this.p.set_zn(*reg);
    }

    // STA STX STY
    fn store(mut this, reg: Reg, typ: Store) {
        this.bus.write(val: *this.register(reg), addr: match typ {
            Store::Zp => {
                this.cycles += 3;
                this.read() as u16
            }
            Store::Zpx => {
                this.cycles += 4;
                this.read().wrapping_add(this.x) as u16
            }
            Store::Zpy => {
                this.cycles += 4;
                this.read().wrapping_add(this.y) as u16
            }
            Store::Abs => {
                this.cycles += 4;
                this.read_u16()
            }
            Store::Abx => {
                this.cycles += 5;
                this.read_u16().wrapping_add(this.x as u16)
            }
            Store::Aby => {
                this.cycles += 5;
                this.read_u16().wrapping_add(this.y as u16)
            }
            Store::Izx => {
                this.cycles += 6;
                this.bus.read_u16_pw(this.read().wrapping_add(this.x) as u16)
            }
            Store::Izy => {
                this.cycles += 6;
                this.bus.read_u16(this.read() as u16).wrapping_add(this.y as u16)
            }
        });
    }

    // TAX TXA TYA TAY TXS TSX
    fn transfer(mut this, kw src: Reg, kw dst: Reg) {
        this.cycles += 2;
        *this.register(dst) = *this.register(src);

        if !(src is Reg::X and dst is Reg::S) {
            this.p.set_zn(*this.register(dst));
        }
    }

    // ORA AND EOR ADC SBC
    fn arithmetic(mut this, load: Load, op: Operation) {
        let val = this.help_load(load);
        this.a = match op {
            :Or  => this.a | val,
            :And => this.a & val,
            :Xor => this.a ^ val,
            :Adc => this.add(this.a, val, carry: this.p.carry, overflow: true),
            :Sbc => this.add(this.a, !val, carry: this.p.carry, overflow: true),
        };
        this.p.set_zn(this.a);
    }

    // ASL LSR ROL ROR
    fn shift(mut this, load: ?IncLoad, typ: Shift) {
        fn help_shift(self: *mut Cpu, val: u8, shift: Shift): u8 {
            let carry = self.p.carry as u8;
            let bit   = if shift is :Ror | :Lsr { 1u8 } else { 1 << 7 };
            self.p.carry = val & bit != 0;
            let val = match shift {
                :Asl => val << 1,
                :Lsr => val >> 1,
                :Rol => (val << 1) | carry,
                :Ror => (val >> 1) | (carry << 7),
            };
            self.p.set_zn(val);
            val
        }

        if load is ?load {
            let (addr, val) = this.inc_load_addr(load);
            this.bus.write(addr, help_shift(this, val, typ));
        } else {
            this.cycles += 2;
            this.a = help_shift(this, this.a, typ);
        }
    }

    // CMP CPX CPY
    fn cmp(mut this, reg: Reg, load: Load) {
        let val = this.help_load(load);
        this.p.set_zn(this.add(*this.register(reg), !val, carry: true, overflow: false));
    }

    // INC DEC
    fn inc_dec(mut this, kw dec: bool, typ: IncLoad) {
        let (addr, val) = this.inc_load_addr(typ);
        let val = if dec { val.wrapping_sub(1) } else { val.wrapping_add(1) };
        this.bus.write(addr, val);
        this.p.set_zn(val);
    }

    // INX INY DEX DEY
    fn inc_dec_reg(mut this, reg: Reg, kw dec: bool) {
        this.cycles += 2;
        let reg = this.register(reg);
        *reg = if dec { reg.wrapping_sub(1) } else { reg.wrapping_add(1) };
        this.p.set_zn(*reg);
    }

    // CLC SEC CLD SED CLI SEI CLV
    fn flag(mut this, flag: Flag, val: bool) {
        this.cycles += 2;
        this.p.set(flag, val);
    }

    // PLA PLP
    fn pull(mut this, dst: Reg) {
        this.cycles += 4;
        let val = this.pop();
        *this.register(dst) = val;
        if !(dst is Reg::P) {
            this.p.set_zn(val);
        }
    }

    // PHA PHP
    fn push_reg(mut this, reg: Reg) {
        this.cycles += 4;
        if reg is Reg::P {
            this.push_flags(interrupt: false);
        } else {
            this.push(*this.register(reg));
        }
    }

    // BPL BMI BVC BVS BCC BCS BNE BEQ
    fn branch(mut this, flag: Flag, enable: bool) {
        let offset = this.read() as u16;
        if this.p.get(flag) == enable {
            let page = this.pc >> 8;
            this.pc = this.pc.wrapping_add(if offset > 0x7f { offset | 0xff00 } else { offset });
            this.cycles += 3 + (page != this.pc >> 8) as u64;
        } else {
            this.cycles += 2;
        }
    }

    fn brk(mut this) {
        this.interrupt(:Brk);
    }

    fn rti(mut this) {
        this.cycles += 6;
        *this.p.as_u8_mut() = this.pop();
        this.pc = this.pop_u16();
    }

    fn jsr(mut this) {
        this.cycles += 6;
        this.push_u16(this.pc.wrapping_add(1));
        this.pc = this.read_u16();
    }

    fn rts(mut this) {
        this.cycles += 6;
        this.pc = this.pop_u16().wrapping_add(1);
    }

    fn jmp(mut this, kw ind: bool) {
        if ind {
            this.cycles += 5;
            this.pc = this.bus.read_u16_pw(this.read_u16());
        } else {
            this.cycles += 3;
            this.pc = this.read_u16();
        }
    }

    fn bit(mut this, kw zp: bool) {
        let val = if zp {
            this.cycles += 3;
            this.bus.read(this.read() as u16)
        } else {
            this.cycles += 4;
            this.bus.read(this.read_u16())
        };

        this.p.zero = val & this.a == 0;
        this.p.negative = val & 0x80 != 0;
        this.p.overflow = val & 0x40 != 0;
    }

    fn nop(mut this) {
        this.cycles += 2;
    }

    // -------------

    impl std::fmt::Format {
        fn fmt(this, f: *mut std::fmt::Formatter) {
            let ins = super::debugger::Instr::decode(&this.bus, this.pc);
            mut buf = "{this.pc:#06x}  \x1b[32m{ins.mnemonic}\x1b[0m ".to_str();
            mut pad = 40u16;
            match ins {
                :Imp(?reg)      => { buf += reg; pad -= 9; },
                :Imm(val)       => buf += "\x1b[35m#${val:02x}\x1b[0m".to_str(),
                :Zp(val, ?reg)  => buf += "\x1b[34m${val:02x}\x1b[0m, {reg}".to_str(),
                :Zp(val, null)  => buf += "\x1b[34m${val:02x}\x1b[0m".to_str(),
                :Izx(val)       => buf += "(\x1b[36m${val:02x}\x1b[0m, X)".to_str(),
                :Izy(val)       => buf += "(\x1b[36m${val:02x}\x1b[0m), Y".to_str(),
                :Ind(val)       => buf += "(\x1b[36m${val:04x}\x1b[0m)".to_str(),
                :Abs(val, ?reg) => buf += "\x1b[36m${val:04x}\x1b[0m, {reg}".to_str(),
                :Abs(val, null) => buf += "\x1b[36m${val:04x}\x1b[0m".to_str(),
                _ => pad -= 9,
            }

            write(f, "{buf:<pad$}; A: \x1b[31m{this.a:02x}\x1b[0m X: \x1b[33m{
                this.x:02x}\x1b[0m Y: \x1b[34m{this.y:02x}\x1b[0m S: \x1b[35m{
                this.s:02x}\x1b[0m P: [\x1b[36m{this.p}\x1b[0m]");
        }
    }
}

pub struct CpuBus {
    pub ppu: Ppu,
    pub apu: Apu,
    pub ipt: Input,
    ram: [u8; 0x800] = [0; 0x800],
    prg_ram: [u8; 0x2000] = [0; 0x2000],
    mapper: *dyn mut Mapper,
    poll_input: [u8; 2] = [0; 2],
    dma_flag: bool = false,

    pub fn new(ipt: Input, mapper: *dyn mut Mapper, pirq: *mut bool, sram: ?[u8..] = null): This {
        mut self = CpuBus(ipt:, mapper:, ppu: Ppu::new(mapper), apu: Apu::new(pirq));
        if sram is ?sram and sram.len() == self.prg_ram.len() {
            self.prg_ram[..] = sram;
        }
        self
    }

    pub fn reset(mut this) {
        this.ppu.reset();
        this.apu.reset();
        this.mapper.reset();
    }

    pub fn write(mut this, addr: u16, val: u8) {
        match addr {
            ..0x2000 => this.ram[addr & 0x7ff] = val,
            ..0x4000 => match addr & 0x2007 {
                0x2000 => this.ppu.write_ctrl(val),
                0x2001 => this.ppu.write_mask(val),
                0x2003 => this.ppu.write_oam_addr(val),
                0x2004 => this.ppu.write_oam(val),
                0x2005 => this.ppu.write_scroll(val),
                0x2006 => this.ppu.write_addr(val),
                0x2007 => this.ppu.write_data(val),
                _ => {}
            }
            ..0x4004 => this.apu.write_reg((addr - 0x4000) as! u2, :Pulse1, val),
            ..0x4008 => this.apu.write_reg((addr - 0x4004) as! u2, :Pulse2, val),
            ..0x400c => this.apu.write_reg((addr - 0x4008) as! u2, :Triangle, val),
            ..0x4010 => this.apu.write_reg((addr - 0x400c) as! u2, :Noise, val),
            ..0x4014 => this.apu.write_reg((addr - 0x4010) as! u2, :Dmc, val),
            0x4014 => {
                for i in 0u8..=255 {
                    this.ppu.write_oam_dma(i, this.read((val as u16 << 8).wrapping_add(i as u16)));
                }
                this.dma_flag = true;
            }
            0x4015 => this.apu.write_status(this, val),
            0x4016 => if val & 1 != 0 { this.poll_input = this.ipt.raw_state(); }
            0x4017 => this.apu.write_frame_counter(val),
            ..0x6000 => eprintln("attempt to write to expansion ROM at {addr:#x}"),
            ..0x8000 => this.prg_ram[addr - 0x6000] = val,
            _ => this.mapper.write_prg(addr, val),
        }
    }

    pub fn read(mut this, addr: u16): u8 {
        match addr {
            ..0x2000 => this.ram[addr & 0x7ff],
            ..0x4000 => match addr & 0x2007 {
                0x2002 => this.ppu.read_status(),
                0x2004 => this.ppu.read_oam(),
                0x2007 => this.ppu.read_data(),
                _ => this.open_bus(),
            }
            0x4015 => this.apu.read_status(),
            0x4016 => {
                let res = this.poll_input[0] & 1;
                this.poll_input[0] >>= 1;
                res
            }
            0x4017 => {
                let res = this.poll_input[1] & 1;
                this.poll_input[1] >>= 1;
                res
            }
            ..0x6000 => {
                eprintln("attempt to read from expansion ROM at {addr:#x}");
                this.open_bus()
            },
            ..0x8000 => this.prg_ram[addr - 0x6000],
            _ => this.mapper.read_prg(addr),
        }
    }

    pub fn read_u16(mut this, addr: u16): u16 {
        (this.read(addr.wrapping_add(1)) as u16 << 8) | this.read(addr) as u16
    }

    pub fn read_u16_pw(mut this, addr: u16): u16 {
        let hi = (addr & 0xff00) + (addr.wrapping_add(1) & 0xff);
        (this.read(hi) as u16 << 8) | this.read(addr) as u16
    }

    pub fn peek(this, addr: u16): u8 {
        match addr {
            ..0x2000 => this.ram[addr & 0x7ff],
            ..0x4000 => match addr & 0x2007 {
                0x2002 => this.ppu.peek_status(),
                0x2004 => this.ppu.read_oam(),
                0x2007 => this.ppu.peek_data(),
                _ => this.open_bus(),
            }
            0x4015 => this.apu.peek_status(),
            0x4016 => this.poll_input[0] & 1,
            0x4017 => this.poll_input[1] & 1,
            ..0x6000 => {
                eprintln("attempt to read from expansion ROM");
                this.open_bus()
            },
            ..0x8000 => this.prg_ram[addr - 0x6000],
            _ => this.mapper.read_prg(addr),
        }
    }

    pub fn peek_u16(this, addr: u16): u16 {
        (this.peek(addr.wrapping_add(1)) as u16 << 8) | this.peek(addr) as u16
    }

    pub fn sram(this): [u8..] => this.prg_ram[..];

    fn open_bus(this): u8 => 0;
}
