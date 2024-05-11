use super::sdl::Color;
use cpu::*;
use ppu::*;
use apu::*;
use mapper::*;
use cart::Cart;

pub union JoystickBtn {
    A,
    B,
    Select,
    Start,
    Up,
    Down,
    Left,
    Right,
}

pub union InputMode {
    Nes,
    AllowOpposing,
    Keyboard,
}

pub struct Input {
    data: [u8; 2] = [0; 2],
    real: [u8; 2] = [0; 2],
    mode: InputMode,

    pub fn new(mode: InputMode): This {
        Input(mode:)
    }

    pub fn press(mut this, btn: JoystickBtn, controller: u1) {
        this.data[controller] |= (1 << btn as u8);
        this.real[controller] |= (1 << btn as u8);
        if !(this.mode is InputMode::AllowOpposing) {
            this.data[controller] &= !(1 << match btn {
                JoystickBtn::Left => JoystickBtn::Right as u8,
                JoystickBtn::Right => JoystickBtn::Left as u8,
                JoystickBtn::Up => JoystickBtn::Down as u8,
                JoystickBtn::Down => JoystickBtn::Up as u8,
                _ => return,
            });
        }
    }

    pub fn release(mut this, btn: JoystickBtn, controller: u1) {
        this.data[controller] &= !(1 << btn as u8);
        this.real[controller] &= !(1 << btn as u8);
        if this.mode is InputMode::Keyboard {
            this.data[controller] |= this.real[controller] & (1 << match btn {
                JoystickBtn::Left => JoystickBtn::Right as u8,
                JoystickBtn::Right => JoystickBtn::Left as u8,
                JoystickBtn::Up => JoystickBtn::Down as u8,
                JoystickBtn::Down => JoystickBtn::Up as u8,
                _ => return,
            });
        }
    }

    pub fn set_mode(mut this, mode: InputMode) {
        this.mode = mode;
    }

    pub fn mode(this): InputMode {
        this.mode
    }

    pub fn raw_state(this): [u8; 2] {
        this.data
    }
}

pub const NTSC_CLOCK_RATE: f64 = 1789772.6;

pub struct Nes {
    cpu: Cpu,
    irq_pending: *mut bool,
    cycle: u64 = 0,
    audio: [f64],

    pub fn new(ipt: Input, cart: Cart, prg_ram: ?[u8..]): Nes {
        let irq_pending = std::alloc::new(false);
        Nes(
            cpu: Cpu::new(CpuBus::new(
                irq_pending:,
                prg_ram:,
                ipt,
                match cart.mapper {
                    0 => std::alloc::new(m000::Nrom::new(cart)),
                    1 => std::alloc::new(m001::Mmc1::new(cart)),
                    2 => std::alloc::new(m002::UxRom::new(cart)),
                    4 => std::alloc::new(m004::Mmc3::new(cart, irq_pending)),
                    9 => std::alloc::new(m009::Mmc2::new(cart)),
                    i => panic("unsupported mapper: {i}"),
                }),
            ),
            irq_pending:,
            audio: @[0.0; (NTSC_CLOCK_RATE * 0.02) as! uint],
        )
    }

    pub fn reset(mut this) {
        this.cpu.reset();
        this.cpu.bus.reset();
        *this.irq_pending = false;
    }

    pub fn input(mut this): *mut Input { &mut this.cpu.bus.ipt }

    pub fn video_buffer(this): [u32..] { this.cpu.bus.ppu.buf[..] }

    pub fn audio_buffer(mut this): [f64..] {
        let buf = this.audio[..];
        this.audio.clear();
        buf
    }

    pub fn sram(this): [u8..] { this.cpu.bus.sram() }

    pub fn cycle(mut this): bool {
        let result = this.cpu.bus.ppu.step();
        if result is PpuResult::VblankNmi {
            this.cpu.nmi_pending = true;
        }

        if this.cycle % 3 == 0 {
            let dmc_stall = this.cpu.bus.apu.step(&mut this.cpu.bus);
            this.audio.push(this.cpu.bus.apu.output());
            if std::mem::replace(this.irq_pending, false) {
                this.cpu.irq_pending = true;
            }

            this.cpu.step(dmc_stall);
        }

        this.cycle++;
        result is PpuResult::Draw
    }

    pub fn toggle_channel_mute(mut this, channel: Channel): bool {
        this.cpu.bus.apu.toggle_channel_mute(channel)
    }
}
