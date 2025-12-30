pub const NTSC_CLOCK_RATE: f64 = 1789772.6;

pub struct Nes {
    cpu: cpu::Cpu,
    bus: *mut bus::Bus,
    apu: *mut apu::Apu,
    ppu: *mut ppu::Ppu,
    ipt: *mut ipt::Input,
    sram: *mut bus::Ram,
    mapper: *dyn mut bus::Mapper,
    signals: *mut cpu::Signals,
    cycle: u64 = 0,
    audio: [f64] = @[0.0; (NTSC_CLOCK_RATE * 0.02) as uint],

    pub fn new(cart: cart::Cart, ipt_mode: ipt::InputMode, prg_ram: ?[u8..]): Nes {
        let signals = std::alloc::new(cpu::Signals());
        let mapper: *dyn mut bus::Mapper = match cart.mapper {
            0 => std::alloc::new(mapper::m000::Nrom::new(cart)),
            1 => std::alloc::new(mapper::m001::Mmc1::new(cart)),
            2 => std::alloc::new(mapper::m002::UxRom::new(cart)),
            4 => std::alloc::new(mapper::m004::Mmc3::new(cart, &mut signals.irq_pending)),
            9 => std::alloc::new(mapper::m009::Mmc2::new(cart)),
            i => panic("unsupported mapper: {i}"),
        };

        let ipt = std::alloc::new(ipt::Input::new(ipt_mode));
        let apu = std::alloc::new(apu::Apu::new(&mut signals.irq_pending));
        let ppu = std::alloc::new(ppu::Ppu::new(mapper, &mut signals.dma_flag));
        let ram = std::alloc::new(bus::Ram::new(0x800, 0x0000u16..0x2000));
        let sram = std::alloc::new(bus::Ram::new(0x2000, 0x6000u16..0x8000));
        if prg_ram is ?prg_ram and prg_ram.len() == sram.buf.len() {
            sram.buf[..] = prg_ram;
        }

        let bus = std::alloc::new(bus::Bus::new(@[ram, ppu, apu, ipt, sram, mapper]));
        let cpu = cpu::Cpu::new(bus, signals);
        Nes(cpu:, apu:, ppu:, bus:, ipt:, sram:, signals:, mapper:)
    }

    pub fn reset(mut this) {
        this.cpu.reset();
        this.apu.reset();
        this.ppu.reset();
        this.mapper.reset();
    }

    pub fn input(mut this): *mut ipt::Input => this.ipt;

    pub fn video_buffer(this): [u32..] => this.ppu.buf;

    pub fn audio_buffer(mut this): [f64..] {
        let buf = this.audio[..];
        this.audio.clear();
        buf
    }

    pub fn sram(this): [u8..] => this.sram.buf;

    pub fn cycle(mut this): bool {
        let draw = this.ppu.step(&mut this.signals.nmi_pending);
        if this.cycle++ % 3 == 0 {
            let dmc_stall = this.apu.step(this.bus);
            this.audio.push(this.apu.output());
            this.cpu.step(dmc_stall);
        }
        draw
    }

    pub fn toggle_channel_mute(mut this, channel: apu::Channel): bool {
        this.apu.toggle_channel_mute(channel)
    }
}
