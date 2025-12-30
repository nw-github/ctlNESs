use super::bus::*;
use super::cpu::*;

pub union Instr {
    shared mnemonic: str,

    Imm(u8),        // #$00
    Zp(u8, ?str),   // $00, X
    Izx(u8),        // ($00, X)
    Izy(u8),        // ($00), Y
    Ind(u16),       // ($0000)
    Abs(u16, ?str), // $0000, X
    Imp(?str),

    fn implied(mnemonic: str): This => Instr::Imp(mnemonic:, null);

    pub fn decode(bus: *Bus, pc: u16): (This, u16) {
        mut dc = Decoder(bus:, pc:);
        let ins = dc.next();
        (ins, dc.pc - pc)
    }
}

pub struct Decoder {
    pub bus: *Bus,
    pub pc: u16,

    pub fn next(mut this): Instr {
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
            opcode => Instr::Imp(mnemonic: "UNK", "{opcode:#02x}".to_str()),
        }
    }

    fn read(mut this): u8 => this.bus.peek(this.pc++);

    fn read_u16(mut this): u16 => this.bus.peek_u16(std::mem::replace(&mut this.pc, this.pc + 2));

    fn load_ins(mut this, mnemonic: str, load: Load): Instr {
        match load {
            Load::Imm => Instr::Imm(mnemonic:, this.read()),
            Load::Zp  => Instr::Zp(mnemonic:, this.read(), null),
            Load::Zpx => Instr::Zp(mnemonic:, this.read(), "X"),
            Load::Zpy => Instr::Zp(mnemonic:, this.read(), "Y"),
            Load::Abs => Instr::Abs(mnemonic:, this.read_u16(), null),
            Load::Abx => Instr::Abs(mnemonic:, this.read_u16(), "X"),
            Load::Aby => Instr::Abs(mnemonic:, this.read_u16(), "Y"),
            Load::Izx => Instr::Izx(mnemonic:, this.read()),
            Load::Izy => Instr::Izy(mnemonic:, this.read()),
        }
    }

    fn store_ins(mut this, mnemonic: str, store: Store): Instr {
        match store {
            Store::Zp  => Instr::Zp(mnemonic:, this.read(), null),
            Store::Zpx => Instr::Zp(mnemonic:, this.read(), "X"),
            Store::Zpy => Instr::Zp(mnemonic:, this.read(), "Y"),
            Store::Abs => Instr::Abs(mnemonic:, this.read_u16(), null),
            Store::Abx => Instr::Abs(mnemonic:, this.read_u16(), "X"),
            Store::Aby => Instr::Abs(mnemonic:, this.read_u16(), "Y"),
            Store::Izx => Instr::Izx(mnemonic:, this.read()),
            Store::Izy => Instr::Izy(mnemonic:, this.read()),
        }
    }

    fn inc_load_ins(mut this, mnemonic: str, load: IncLoad): Instr {
        match load {
            IncLoad::Zp  => Instr::Zp(mnemonic:, this.read(), null),
            IncLoad::Zpx => Instr::Zp(mnemonic:, this.read(), "X"),
            IncLoad::Abs => Instr::Abs(mnemonic:, this.read_u16(), null),
            IncLoad::Abx => Instr::Abs(mnemonic:, this.read_u16(), "X"),
        }
    }

    // ------

    fn load(mut this, reg: Reg, load: Load): Instr {
        this.load_ins(load:, mnemonic: match reg {
            Reg::A => "LDA",
            Reg::X => "LDX",
            Reg::Y => "LDY",
            _ => panic("invalid load instruction"),
        })
    }

    fn store(mut this, reg: Reg, store: Store): Instr {
        this.store_ins(store:, mnemonic: match reg {
            Reg::A => "STA",
            Reg::X => "STX",
            Reg::Y => "STY",
            _ => panic("invalid store instruction"),
        })
    }

    fn transfer(mut this, kw src: Reg, kw dst: Reg): Instr {
        Instr::implied(match (src, dst) {
            (Reg::A, Reg::X) => "TAX",
            (Reg::X, Reg::A) => "TXA",
            (Reg::A, Reg::Y) => "TAY",
            (Reg::Y, Reg::A) => "TYA",
            (Reg::X, Reg::S) => "TXS",
            (Reg::S, Reg::X) => "TSX",
            _ => panic("invalid transfer instruction"),
        })
    }

    fn arithmetic(mut this, load: Load, op: Operation): Instr {
        this.load_ins(load:, mnemonic: match op {
            Operation::Adc => "ADC",
            Operation::Sbc => "SBC",
            Operation::And => "AND",
            Operation::Or  => "ORA",
            Operation::Xor => "EOR",
        })
    }

    fn shift(mut this, load: ?IncLoad, typ: Shift): Instr {
        match (typ, load) {
            (Shift::Asl, ?load) => this.inc_load_ins("ASL", load),
            (Shift::Lsr, ?load) => this.inc_load_ins("LSR", load),
            (Shift::Rol, ?load) => this.inc_load_ins("ROL", load),
            (Shift::Ror, ?load) => this.inc_load_ins("ROR", load),
            (Shift::Asl, null) => Instr::Imp(mnemonic: "ASL", "A"),
            (Shift::Lsr, null) => Instr::Imp(mnemonic: "LSR", "A"),
            (Shift::Rol, null) => Instr::Imp(mnemonic: "ROL", "A"),
            (Shift::Ror, null) => Instr::Imp(mnemonic: "ROR", "A"),
            _ => unreachable(),
        }
    }

    fn cmp(mut this, reg: Reg, load: Load): Instr {
        this.load_ins(load:, mnemonic: match reg {
            Reg::A => "CMP",
            Reg::X => "CPX",
            Reg::Y => "CPY",
            _ => panic("invalid compare instruction"),
        })
    }

    fn inc_dec(mut this, kw dec: bool, typ: IncLoad): Instr {
        this.inc_load_ins(if dec { "DEC" } else { "INC" }, typ)
    }

    fn inc_dec_reg(mut this, reg: Reg, kw dec: bool): Instr {
        Instr::implied(match (reg, dec) {
            (Reg::X, false) => "INX",
            (Reg::X, true) => "DEX",
            (Reg::Y, false) => "INY",
            (Reg::Y, true) => "DEY",
            _ => panic("invalid increment instruction"),
        })
    }

    fn flag(mut this, flag: Flag, val: bool): Instr {
        Instr::implied(match (flag, val) {
            (Flag::Carry, true) => "SEC",
            (Flag::Carry, false) => "CLC",
            (Flag::Decimal, true) => "SED",
            (Flag::Decimal, false) => "CLD",
            (Flag::IntDisable, true) => "SEI",
            (Flag::IntDisable, false) => "CLI",
            (Flag::Overflow, false) => "CLV",
            _ => panic("invalid flag instruction"),
        })
    }

    fn pull(mut this, dst: Reg): Instr {
        Instr::implied(match dst {
            Reg::A => "PLA",
            Reg::P => "PLP",
            _ => panic("invalid pull instruction"),
        })
    }

    fn push_reg(mut this, reg: Reg): Instr {
        Instr::implied(match reg {
            Reg::A => "PHA",
            Reg::P => "PHP",
            _ => panic("invalid pull instruction"),
        })
    }

    fn branch(mut this, flag: Flag, enable: bool): Instr {
        let mnemonic = match (flag, enable) {
            (Flag::Negative, false) => "BPL",
            (Flag::Negative, true) => "BMI",
            (Flag::Overflow, false) => "BVC",
            (Flag::Overflow, true) => "BVS",
            (Flag::Carry, false) => "BCC",
            (Flag::Carry, true) => "BCS",
            (Flag::Zero, false) => "BNE",
            (Flag::Zero, true) => "BEQ",
            _ => panic("invalid branch instruction"),
        };

        let offset = this.read() as u16;
        let target = this.pc.wrapping_add(offset > 0x7f then offset | 0xff00 else offset);
        Instr::Abs(mnemonic:, target, null)
    }

    fn jsr(mut this): Instr => Instr::Abs(mnemonic: "JSR", this.read_u16(), null);

    fn jmp(mut this, kw ind: bool): Instr {
        if ind {
            Instr::Ind(mnemonic: "JMP", this.read_u16())
        } else {
            Instr::Abs(mnemonic: "JMP", this.read_u16(), null)
        }
    }

    fn bit(mut this, kw zp: bool): Instr {
        if zp {
            Instr::Zp(mnemonic: "BIT", this.read(), null)
        } else {
            Instr::Abs(mnemonic: "BIT", this.read_u16(), null)
        }
    }

    fn brk(this): Instr => Instr::implied("BRK");
    fn rti(this): Instr => Instr::implied("RTI");
    fn rts(this): Instr => Instr::implied("RTS");
    fn nop(this): Instr => Instr::implied("NOP");
}
