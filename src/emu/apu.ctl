use super::cpu::CpuBus;

pub union Channel {
    Pulse1,
    Pulse2,
    Triangle,
    Noise,
    Dmc,
}

pub struct Apu {
    cycles: uint = 0,
    seq_step: uint = 0,
    irq_pending: *mut bool,
    irq_enabled: bool = false,
    five_step_mode: bool = false,

    pulse1: Pulse = Pulse(),
    pulse2: Pulse = Pulse(),
    tri: Triangle = Triangle(),
    noise: Noise = Noise(),
    dmc: Dmc = Dmc(),

    pub fn new(irq_pending: *mut bool): This {
        Apu(irq_pending:)
    }

    pub fn reset(mut this) {
        this.cycles = 0;
        this.seq_step = 0;
        this.write_frame_counter(0);
    }

    pub fn step(mut this, bus: *mut CpuBus): bool {
        const CLOCK_RATE: uint = 1789773; // 1789772.6

        this.cycles++;
        if this.cycles % 2 != 0 {
            this.pulse1.clock();
            this.pulse2.clock();
            this.noise.clock();
            this.dmc.clock(bus, this.irq_pending);
        }
        this.tri.clock();

        if this.cycles % (CLOCK_RATE / 240) == 0 {
            this.clock_quarter_frame();

            let step = this.seq_step % 5;
            if step % 2 == !this.five_step_mode as uint {
                this.clock_half_frame();
            }

            if !this.five_step_mode and step == 3 and this.irq_enabled {
                *this.irq_pending = true;
            }

            this.seq_step++;
        }

        std::mem::replace(&mut this.dmc.stall, false)
    }

    pub fn write_reg(mut this, reg: u2, channel: Channel, val: u8) {
        match channel {
            Channel::Pulse1 => match reg {
                0 => this.pulse1.write_reg1(val),
                1 => this.pulse1.sweep.write(val),
                2 => this.pulse1.tmr.set_lo(val),
                3 => this.pulse1.write_reg4(val),
            }
            Channel::Pulse2 => match reg {
                0 => this.pulse2.write_reg1(val),
                1 => this.pulse2.sweep.write(val),
                2 => this.pulse2.tmr.set_lo(val),
                3 => this.pulse2.write_reg4(val),
            }
            Channel::Triangle => match reg {
                0 => {
                    this.tri.len_count.enabled = val & (1 << 7) == 0;
                    this.tri.lin_count.enabled = val & (1 << 7) == 0;
                    this.tri.lin_count.load = (val & 0x7f) as! u7;
                }
                1 => {}
                2 => this.tri.tmr.set_lo(val),
                3 => {
                    this.tri.tmr.set_hi(val);
                    this.tri.lin_count.reset = true;
                    this.tri.tmr.val = this.tri.tmr.reload;
                    if this.tri.enabled {
                        this.tri.len_count.load(val);
                    }
                }
            }
            Channel::Noise => match reg {
                0 => {
                    this.noise.len_count.enabled = val & (1 << 5) == 0;
                    this.noise.envelope.load(val);
                }
                1 => {}
                2 => {
                    this.noise.mode = val & (1 << 7) != 0;
                    this.noise.tmr.reload = NOISE_PERIOD_TABLE[val & 0xf];
                }
                3 => {
                    this.noise.len_count.load(val);
                    this.noise.envelope.reset = true;
                }
            }
            Channel::Dmc => match reg {
                0 => {
                    this.dmc.irq_enable = val & (1 << 7) != 0;
                    this.dmc.loops = val & (1 << 6) != 0;
                    this.dmc.tmr.reload = DMC_PERIOD_TABLE[val & 0xf];
                }
                1 => this.dmc.output_val = val & 0x7f,
                2 => this.dmc.addr = 0xc000 + (val as u16 << 6),
                3 => this.dmc.length = (val as u16 << 4) + 1,
            }
        }
    }

    // r $4015
    pub fn read_status(mut this): u8 {
        let val = this.peek_status();
        this.irq_enabled = false;
        val
    }

    // r $4015
    pub fn peek_status(this): u8 {
        (this.dmc.irq_enable as u8 << 7)
            | (this.irq_enabled as u8 << 6)
            | ((this.dmc.read_remaining != 0) as u8 << 4)
            | ((this.noise.len_count.val != 0) as u8 << 3)
            | ((this.tri.len_count.val != 0) as u8 << 2)
            | ((this.pulse2.len_count.val != 0) as u8 << 1)
            | ((this.pulse1.len_count.val != 0) as u8 << 0)
    }

    pub fn write_status(mut this, bus: *mut CpuBus, val: u8) {
        this.dmc.enabled = val & (1 << 4) != 0;
        this.noise.enabled = val & (1 << 3) != 0;
        this.tri.enabled = val & (1 << 2) != 0;
        this.pulse2.enabled = val & (1 << 1) != 0;
        this.pulse1.enabled = val & (1 << 0) != 0;
        if !this.noise.enabled {
            this.noise.len_count.val = 0;
        }
        if !this.tri.enabled {
            this.tri.len_count.val = 0;
        }
        if !this.pulse2.enabled {
            this.pulse2.len_count.val = 0;
        }
        if !this.pulse1.enabled {
            this.pulse1.len_count.val = 0;
        }
        if !this.dmc.enabled {
            this.dmc.read_remaining = 0;
        } else if this.dmc.read_remaining == 0 {
            this.dmc.read_addr = this.dmc.addr;
            this.dmc.read_remaining = this.dmc.length;
            if this.dmc.out_shift_reg == 0 {
                this.dmc.transfer(bus, this.irq_pending);
            }
        }
    }

    // w $4017
    pub fn write_frame_counter(mut this, val: u8) {
        this.five_step_mode = val & (1 << 7) != 0;
        this.irq_enabled = val & (1 << 6) == 0; // this is actually the IRQ inhibit flag
        // disable the pending irq?
        // if this.five_step_mode {
        //     this.clock();
        //     this.clock_half_frame();
        // }
    }

    pub fn toggle_channel_mute(mut this, channel: Channel): bool {
        match channel {
            Channel::Pulse1 => { this.pulse1.muted = !this.pulse1.muted; this.pulse1.muted },
            Channel::Pulse2 => { this.pulse2.muted = !this.pulse2.muted; this.pulse2.muted },
            Channel::Noise => { this.noise.muted = !this.noise.muted; this.noise.muted },
            Channel::Triangle => { this.tri.muted = !this.tri.muted; this.tri.muted },
            Channel::Dmc => { this.dmc.muted = !this.dmc.muted; this.dmc.muted },
        }
    }

    pub fn output(this): f64 {
        let pulse = this.pulse1.output() + this.pulse2.output();
        let tnd   = this.tri.output() * 3 + this.noise.output() * 2 + this.dmc.output();
        PULSE_TABLE[pulse as uint % PULSE_TABLE.len()] + TND_TABLE[tnd as uint % TND_TABLE.len()]
    }

    fn clock_quarter_frame(mut this) {
        this.pulse1.envelope.clock();
        this.pulse2.envelope.clock();
        this.tri.lin_count.clock();
        this.noise.envelope.clock();
    }

    fn clock_half_frame(mut this) {
        this.pulse1.clock_half_frame(false);
        this.pulse2.clock_half_frame(true);
        this.tri.len_count.clock();
        this.noise.len_count.clock();
    }
}

struct Envelope {
    enabled: bool = false,
    loops: bool = false,
    reset: bool = false,
    constant_volume: u4 = 0,
    step: u4 = 0,
    val: u4 = 0,

    pub fn load(mut this, val: u8) {
        this.loops = val & (1 << 5) != 0;
        this.enabled = val & (1 << 4) == 0;
        this.constant_volume = (val & 0xf) as! u4;
        // this.reset = true;
    }

    pub fn clock(mut this) {
        guard !this.reset else {
            this.val = u4::max_value();
            this.step = this.constant_volume;
            this.reset = false;
            return;
        }

        if this.step == 0 {
            this.step = this.constant_volume;
            if this.val != 0 {
                this.val--;
            } else if this.loops {
                this.val = u4::max_value();
            }
        } else {
            this.step--;
        }
    }

    pub fn output(this): u8 {
        if this.enabled {
            this.val as u8
        } else {
            this.constant_volume as u8
        }
    }
}

struct LenCounter {
    enabled: bool = false,
    val: u8 = 0,

    pub fn clock(mut this) {
        if this.enabled and this.val != 0 {
            this.val--;
        }
    }

    pub fn load(mut this, val: u8) {
        this.val = LEN_COUNTER_TABLE[val >> 3];
    }
}

struct Sweep {
    enabled: bool = false,
    period: u3 = 0,
    negate: bool = false,
    shift: u3 = 0,

    val: u8 = 0,
    reset: bool = false,

    pub fn write(mut this, val: u8) {
        this.enabled = val & (1 << 7) != 0;
        this.period = ((val >> 4) & 7) as! u3;
        this.negate = val & (1 << 3) != 0;
        this.shift = (val & 0x7) as! u3;
        this.reset = true;
    }
}

struct Timer {
    val: u16 = 0,
    reload: u16 = 0,

    pub fn set_lo(mut this, val: u8) {
        this.reload = (this.reload & !0xff) | val as u16;
    }

    pub fn set_hi(mut this, val: u8) {
        this.reload = (this.reload & 0xff) | (val as u16 & 0x7) << 8;
    }

    pub fn clock(mut this): bool {
        if this.val == 0 {
            this.val = this.reload;
            true
        } else {
            this.val--;
            false
        }
    }
}

struct Pulse {
    duty: u2 = 0,
    sweep: Sweep = Sweep(),
    duty_val: u3 = 0,
    enabled: bool = false,
    tmr: Timer = Timer(),
    envelope: Envelope = Envelope(),
    len_count: LenCounter = LenCounter(),
    muted: bool = false,

    pub fn write_reg1(mut this, val: u8) {
        this.duty = (val >> 6) as! u2;
        this.len_count.enabled = val & (1 << 5) == 0;
        this.envelope.load(val);
    }

    pub fn write_reg4(mut this, val: u8) {
        if this.enabled {
            this.len_count.load(val);
        }
        this.tmr.set_hi(val);
        this.envelope.reset = true;
        this.tmr.val = 0;
        this.duty_val = 0;
    }

    pub fn clock(mut this) {
        if this.tmr.clock() {
            this.duty_val = this.duty_val.wrapping_add(1);
        }
    }

    pub fn clock_half_frame(mut this, is_pulse2: bool) {
        this.len_count.clock();
        guard !this.sweep.reset else {
            this.sweep.val = this.sweep.period as u8 + 1;
            this.sweep.reset = false;
            return;
        }

        if this.sweep.val == 0 {
            this.sweep.val = this.sweep.period as u8 + 1;
            guard this.sweep.enabled else {
                return;
            }

            if !this.sweep.negate {
                this.tmr.reload += this.tmr.reload >> this.sweep.shift;
            } else if !is_pulse2 {
                this.tmr.reload -= (this.tmr.reload >> this.sweep.shift) + 1;
            } else {
                this.tmr.reload -= (this.tmr.reload >> this.sweep.shift);
            }
        } else {
            this.sweep.val--;
        }
    }

    pub fn output(this): u8 {
        guard DUTY_TABLE[this.duty][this.duty_val]
            and this.tmr.val >= 8
            and this.tmr.reload <= 0x7ff
            and this.enabled
            and this.len_count.val != 0
            and !this.muted
        else {
            return 0;
        }

        this.envelope.output()
    }
}

struct LinearCounter {
    load: u7 = 0,
    val: u16 = 0,
    reset: bool = false,
    enabled: bool = false,

    pub fn clock(mut this) {
        if this.reset {
            this.val = this.load as u16;
        } else if this.val != 0 {
            this.val--;
        }

        if this.enabled {
            this.reset = false;
        }
    }
}

struct Triangle {
    tmr: Timer = Timer(),
    len_count: LenCounter = LenCounter(),
    lin_count: LinearCounter = LinearCounter(),
    enabled: bool = false,
    duty_val: u5 = 0,
    muted: bool = false,

    pub fn clock(mut this) {
        if this.tmr.clock() {
            this.duty_val = this.duty_val.wrapping_add(1);
        }
    }

    pub fn output(this): u8 {
        guard this.enabled
            and this.len_count.val != 0
            and this.lin_count.val != 0
            and !this.muted
        else {
            return 0;
        }

        TRIANGLE_TABLE[this.duty_val]
    }
}

struct Noise {
    mode: bool = false,
    len_count: LenCounter = LenCounter(),
    envelope: Envelope = Envelope(),
    tmr: Timer = Timer(),
    enabled: bool = false,
    shift_reg: u16 = 1,
    muted: bool = false,

    pub fn clock(mut this) {
        if this.tmr.clock() {
            let bit = this.mode then 6u32 else 1;
            let feedback = (this.shift_reg & 1) ^ ((this.shift_reg >> bit) & 1);
            this.shift_reg = (this.shift_reg >> 1) | (feedback << 14);
        }
    }

    pub fn output(this): u8 {
        guard this.enabled
            and this.len_count.val != 0
            and this.shift_reg & 1 == 0
            and !this.muted
        else {
            return 0;
        }

        this.envelope.output()
    }
}

struct Dmc {
    irq_enable: bool = false,
    loops: bool = false,
    addr: u16 = 0,
    length: u16 = 0,
    tmr: Timer = Timer(),
    output_val: u8 = 0,
    enabled: bool = false,
    read_addr: u16 = 0,
    read_remaining: u16 = 0,
    out_shift_reg: u8 = 0,
    out_bits_remaining: u8 = 0,
    silence: bool = false,
    read_buf: ?u8 = null,
    stall: bool = false,
    muted: bool = false,

    pub fn clock(mut this, bus: *mut CpuBus, irq_pending: *mut bool) {
        guard this.tmr.clock() else {
            return;
        }

        if !this.silence {
            if this.out_shift_reg & 1 != 0 {
                this.output_val += this.output_val <= 125 then 2 else 1;
            } else {
                this.output_val -= this.output_val >= 2 then 2 else 1;
            }
            this.out_shift_reg >>= 1;
        }

        if this.out_bits_remaining != 0 {
            this.out_bits_remaining--;
        }

        guard this.out_bits_remaining == 0 else {
            return;
        }

        this.out_bits_remaining = 8;
        if this.read_buf.take() is ?data {
            this.silence = false;
            this.out_shift_reg = data;
            this.transfer(bus, irq_pending);
        } else {
            this.silence = true;
        }
    }

    pub fn transfer(mut this, bus: *mut CpuBus, irq_pending: *mut bool) {
        guard this.read_remaining != 0 and this.read_buf is null else {
            return;
        }

        this.stall = true;
        this.read_buf = bus.read(this.read_addr++);
        if this.read_addr == 0 {
            this.read_addr = 0x8000;
        }

        guard --this.read_remaining == 0 else {
            return;
        }

        if this.loops {
            this.read_addr = this.addr;
            this.read_remaining = this.length;
        } else if this.irq_enable {
            *irq_pending = true;
        }
    }

    pub fn output(this): u8 {
        guard this.enabled and !this.muted else {
            return 0;
        }

        this.output_val
    }
}

// https://www.nesdev.org/wiki/APU_Mixer#Emulation

static PULSE_TABLE: [f64; 31] = {
    mut table = [0.0; 31];
    for (i, v) in table.iter_mut().enumerate() {
        *v = 95.52 / (8128.0 / i as f64 + 100.0);
    }
    table
};

static TND_TABLE: [f64; 203] = {
    mut table = [0.0; 203];
    for (i, v) in table.iter_mut().enumerate() {
        *v = 163.67 / (24329.0 / i as f64 + 100.0);
    }
    table
};

static DUTY_TABLE: [[bool; 8]; 4] = [
    [false, true , false, false, false, false, false, false],
    [false, true , true , false, false, false, false, false],
    [false, true , true , true , true , false, false, false],
    [true , false, false, true , true , true , true , true ],
];

static LEN_COUNTER_TABLE: [u8; 32] = [
    10, 254, 20,  2, 40,  4, 80,  6, 160,  8, 60, 10, 14, 12, 26, 14,
    12,  16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30
];

static TRIANGLE_TABLE: [u8; 32] = [
    15, 14, 13, 12, 11, 10, 9, 8, 7, 6,  5,  4,  3,  2,  1,  0,
    0,   1,  2,  3,  4,  5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
];

static NOISE_PERIOD_TABLE: [u16; 16] = [
    4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068,
];

static DMC_PERIOD_TABLE: [u16; 16] = [
  428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54,
];