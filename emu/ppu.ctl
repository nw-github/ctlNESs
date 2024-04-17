use super::mapper::Mapper;
use super::cart::Mirroring;
use ctlness::sdl::Color;

pub const HPIXELS: uint = 256;
pub const VPIXELS: uint = 240;

const SCANLINE_END_CYCLE: u16 = 340;

struct Ctrl {
    val: u8,

    pub fn nmi_enable(this): bool { this.val & (1 << 7) != 0 }
    pub fn master_slave(this): bool { this.val & (1 << 6) != 0 }
    pub fn long_sprites(this): bool { this.val & (1 << 5) != 0 }
    pub fn bg_tile_addr(this): u16 { (this.val & (1 << 4) != 0) as u16 << 12 }
    pub fn sprite_tile_addr(this): u16 { (this.val & (1 << 3) != 0) as u16 << 12 }
    pub fn increment(this): u16 { if this.val & (1 << 2) != 0 { 32 } else { 1 } }
    pub fn nametable_select(this): u8 { this.val & 0b11 }
}

struct Mask {
    val: u8,

    pub fn emphasize_blue(this): bool { this.val & (1 << 7) != 0 }
    pub fn emphasize_green(this): bool { this.val & (1 << 6) != 0 }
    pub fn emphasize_red(this): bool { this.val & (1 << 5) != 0 }
    pub fn show_sprites(this): bool { this.val & (1 << 4) != 0 }
    pub fn show_bg(this): bool { this.val & (1 << 3) != 0 }
    pub fn show_sprites_l8(this): bool { this.val & (1 << 2) != 0 }
    pub fn show_bg_l8(this): bool { this.val & (1 << 1) != 0 }
    pub fn greyscale(this): bool { this.val & 1 != 0 }
}

union State {
    PreRender,
    Render,
    PostRender,
    VBlank,
}

pub union PpuResult {
    Draw,
    VblankNmi,
    None,
}

pub struct Ppu {
    pub buf: [mut u32..] = @[0u32; HPIXELS * VPIXELS][..],

    bus: PpuBus,
    oam: [u8; 64 * 4] = [0; 64 * 4],
    sprites: [u8; 8] = [0; 8],
    sprite_count: uint = 0,
    state: State = State::PreRender,
    cycle: u16 = 0,
    scanline: u16 = 0,
    even_frame: bool = true,
    vblank: bool = false,
    spr_zero_hit: bool = false,
    spr_overflow: bool = false,

    ctrl: Ctrl = Ctrl(val: 0),
    mask: Mask = Mask(val: 0x18),
    v: u16 = 0,      // scroll position while rendering, vram addr otherwise
    t: u16 = 0,      // starting coarse x scroll and starting y scroll while rendering,
                     // scroll/tmp vram addr otherwise
    x: u8 = 0,       // fine x position for current scroll
    w: bool = false, // write latch for ppuscroll/ppuaddr
    oam_addr: u8 = 0,
    data_buf: u8 = 0,

    pub fn new(mapper: *dyn mut Mapper): This {
        Ppu(bus: PpuBus::new(mapper))
    }

    pub fn reset(mut this) {
        this.cycle = 0;
        this.even_frame = true;
        this.scanline = 0;
        this.data_buf = 0;
        this.ctrl.val = 0;
        this.mask.val = 0;
        this.w = false;
    }

    pub fn step(mut this): PpuResult {
        mut result = PpuResult::None;
        match this.state {
            State::PreRender => {
                let rendering_on = this.mask.show_bg() and this.mask.show_sprites();
                if this.cycle == 1 {
                    this.vblank = false;
                    this.spr_zero_hit = false;
                } else if this.cycle == HPIXELS as! u16 + 2 and rendering_on {
                    this.v = (this.v & !0x41f) | (this.t & 0x41f);
                } else if this.cycle is 281..=304 and rendering_on {
                    this.v = (this.v & !0x7be0) | (this.t & 0x7be0);
                }

                if this.cycle >= SCANLINE_END_CYCLE - (!this.even_frame and rendering_on) as u16 {
                    this.state = State::Render;
                    this.cycle = 0;
                    this.scanline = 0;
                }

                if this.cycle == 260 and rendering_on {
                    this.bus.mapper.scanline();
                }
            }
            State::Render => this.render(),
            State::PostRender => {
                if this.cycle >= SCANLINE_END_CYCLE {
                    this.scanline++;
                    this.cycle = 0;
                    this.state = State::VBlank;
                    result = PpuResult::Draw;
                }
            }
            State::VBlank => {
                if this.cycle == 1 and this.scanline == VPIXELS as! u16 + 1 {
                    this.vblank = true;
                    if this.ctrl.nmi_enable() {
                        result = PpuResult::VblankNmi;
                    }
                }
                if this.cycle >= SCANLINE_END_CYCLE {
                    this.scanline++;
                    this.cycle = 0;
                }
                if this.scanline >= 261 {
                    this.state = State::PreRender;
                    this.scanline = 0;
                    this.even_frame = !this.even_frame;
                }
            }
        }

        this.cycle++;
        result
    }

    fn render(mut this) {
        let show_bg = this.mask.show_bg();
        let show_spr = this.mask.show_sprites();
        if this.cycle > 0 and this.cycle <= HPIXELS as! u16 {
            mut [bg_color, spr_color] = [0u8; 2];
            mut [bg_opaque, spr_opaque] = [false, true];
            mut spr_foreground = false;
            let [x, y] = [this.cycle - 1, this.scanline];
            if show_bg {
                let x_fine = (this.x as u16 + x) % 8;
                if this.mask.show_bg_l8() or x >= 8 {
                    let tile = this.bus.read((this.v & 0xfff) | 0x2000) as u16;
                    let addr = (tile * 16 + ((this.v >> 12) & 0x7)) | this.ctrl.bg_tile_addr();

                    bg_color = (this.bus.read(addr) >> (x_fine ^ 7)) & 1;
                    bg_color |= ((this.bus.read(addr + 8) >> (x_fine ^ 7)) & 1) << 1;
                    bg_opaque = bg_color != 0;

                    let attr = this.bus.read(
                        0x23c0 | (this.v & 0xc00) | ((this.v >> 4) & 0x38) | ((this.v >> 2) & 0x7)
                    );
                    let shift = ((this.v >> 4) & 4) | (this.v & 2);
                    bg_color |= ((attr >> shift) & 3) << 2;
                }
                if x_fine == 7 {
                    if this.v & 0x1f == 31 {
                        this.v = (this.v & !0x1f) ^ 0x400;
                    } else {
                        this.v++;
                    }
                }
            }

            if show_spr and (this.mask.show_sprites_l8() or x >= 8) {
                for i in this.sprites[..this.sprite_count].iter() {
                    let spr_x = this.oam[i * 4 + 3] as u16;
                    if x < spr_x or x - spr_x >= 8 {
                        continue;
                    }

                    let spr_y   = (this.oam[i * 4] + 1) as u16;
                    let tile    = this.oam[i * 4 + 1] as u16;
                    let attr    = this.oam[i * 4 + 2];
                    let len     = if this.ctrl.long_sprites() { 16u16 } else { 8 };
                    mut x_shift = (x - spr_x) % 8;
                    mut y_offs  = (y - spr_y) % len;
                    if attr & 0x40 == 0 {
                        x_shift ^= 7;
                    }
                    if attr & 0x80 != 0 {
                        y_offs ^= len - 1;
                    }

                    let addr = if !this.ctrl.long_sprites() {
                        tile * 16 + y_offs + this.ctrl.sprite_tile_addr()
                    } else {
                        y_offs = (y_offs & 7) | ((y_offs & 8) << 1);
                        ((tile >> 1) * 32 + y_offs) | ((tile & 1) << 12)
                    };

                    spr_color |= (this.bus.read(addr) >> x_shift) & 1;
                    spr_color |= ((this.bus.read(addr + 8) >> x_shift) & 1) << 1;
                    spr_opaque = spr_color != 0;
                    if !spr_opaque {
                        continue;
                    }

                    spr_color |= 0x10 | (attr & 3) << 2;
                    spr_foreground = attr & 0x20 == 0;
                    if !this.spr_zero_hit and show_bg and i == 0 and spr_opaque and bg_opaque {
                        this.spr_zero_hit = true;
                    }
                    break;
                }
            }

            let palette = if 
                (!bg_opaque and spr_opaque) or (bg_opaque and spr_opaque and spr_foreground)
            {
                spr_color                
            } else if !bg_opaque and !spr_opaque {
                0
            } else {
                bg_color
            };

            mut idx = this.bus.read(0x3f00 + (palette as u16));
            if idx as uint >= PALETTE[..].len() {
                // eprintln("attempt to render bad palette index {idx}");
                idx = 0;
            }
            this.buf[x + y * HPIXELS as! u16] = PALETTE[idx].to_abgr32();
        } else if this.cycle == HPIXELS as! u16 + 1 and show_bg {
            if this.v & 0x7000 != 0x7000 { // if fine Y < 7
                this.v += 0x1000;             // increment fine Y
            } else {
                this.v &= !0x7000;              // fine Y = 0
                mut y = (this.v & 0x3e0) >> 5; // let y = coarse Y
                if y == 29 {
                    y = 0;                   // coarse Y = 0
                    this.v ^= 0x800; // switch vertical nametable
                } else if y == 31 {
                    y = 0; // coarse Y = 0, nametable not switched
                } else {
                    y++; // increment coarse Y
                }
                this.v = (this.v & !0x3e0) | (y << 5);
                // put coarse Y back into m_dataAddress
            }
        } else if this.cycle == HPIXELS as! u16 + 2 and show_bg and show_spr {
            this.v = (this.v & !0x41f) | (this.t & 0x41f);
        }

        if this.cycle == 260 and show_bg and show_spr {
            this.bus.mapper.scanline();
        }

        if this.cycle >= SCANLINE_END_CYCLE {
            this.sprite_count = 0;

            let range = if this.ctrl.long_sprites() { 16u16 } else { 8 };
            for i in this.oam_addr / 4..64 {
                let spr_y = this.oam[i * 4] as u16;
                if this.scanline >= spr_y and this.scanline - spr_y < range {
                    if this.sprite_count == this.sprites[..].len() {
                        this.spr_overflow = true;
                        break;
                    }

                    this.sprites[this.sprite_count++] = i;
                }
            }

            this.scanline++;
            this.cycle = 0;
        }

        if this.scanline >= VPIXELS as! u16 {
            this.state = State::PostRender;
        }
    }

    // r $2002
    pub fn read_status(mut this): u8 {
        let status = this.peek_status();
        this.vblank = false;
        this.w = false;
        status
    }

    // r $2002
    pub fn peek_status(this): u8 {
        // TODO: lower 5 bits should be PPU open bus
        this.vblank as u8 << 7 | this.spr_zero_hit as u8 << 6 | this.spr_overflow as u8 << 5
    }

    // r $2004
    pub fn read_oam(this): u8 {
        this.oam[this.oam_addr]
    }

    // r $2007
    pub fn read_data(mut this): u8 {
        let val = this.peek_data();
        defer this.v += this.ctrl.increment();
        // reads from anywhere except palette memory are delayed by one
        if this.v < 0x3f00 {
            std::mem::replace(&mut this.data_buf, val)
        } else {
            val
        }
    }

    // r $2007
    pub fn peek_data(this): u8 {
        this.bus.read(this.v)
    }

    // w $2000
    pub fn write_ctrl(mut this, val: u8) {
        this.ctrl.val = val;
        this.t = (this.t & !0xc00) | (this.ctrl.nametable_select() as u16 << 10);
    }

    // w $2001
    pub fn write_mask(mut this, val: u8) {
        this.mask.val = val;
    }

    // w $2003
    pub fn write_oam_addr(mut this, val: u8) {
        this.oam_addr = val;
    }

    // w $2004
    pub fn write_oam(mut this, val: u8) {
        this.oam[this.oam_addr++] = val;
    }

    // w $2005
    pub fn write_scroll(mut this, val: u8) {
        if !this.w {
            this.t = (this.t & !0x1f) | ((val as u16 >> 3) & 0x1f);
            this.x = val & 0x7;
        } else {
            let val = val as u16;
            this.t = (this.t & !0x73e0) | ((val & 0x7) << 12) | ((val & 0xf8) << 2);
        }
        this.w = !this.w;
    }

    // w $2006
    pub fn write_addr(mut this, val: u8) {
        if !this.w {
            this.t = (this.t & !0xff00) | ((val as u16 & 0x3f) << 8);
        } else {
            this.t = (this.t & !0xff) | val as u16;
            this.v = this.t;
        }
        this.w = !this.w;
    }

    // w $2007
    pub fn write_data(mut this, val: u8) {
        this.bus.write(this.v, val);
        this.v += this.ctrl.increment();
    }

    // w $4014
    pub fn write_oam_dma(mut this, idx: u8, val: u8) {
        this.oam[this.oam_addr.wrapping_add(idx)] = val;
    }
}

struct PpuBus {
    palette: [u8; 0x20] = [0; 0x20],
    ram: [u8; 0x800] = [0; 0x800],
    mapper: *dyn mut Mapper,

    pub fn new(mapper: *dyn mut Mapper): This {
        PpuBus(mapper:)
    }

    pub fn read(this, addr: u16): u8 {
        match addr {
            ..0x2000 => this.mapper.read_chr(addr),
            ..0x3f00 => {
                let normalized = if addr >= 0x3000 { addr - 0x1000 } else { addr };
                if this.get_nametable_addr(normalized) is ?nametable {
                    this.ram[nametable + (addr & 0x3ff)]
                } else {
                    this.mapper.read_chr(normalized)
                }
            }
            ..0x3fff => {
                mut idx = (addr & 0x1f) as! u8;
                if idx >= 0x10 and idx % 4 == 0 {
                    idx &= 0xf;
                }
                this.palette[idx]
            },
            _ => 0, // TODO: open bus?
        }
    }

    pub fn write(mut this, addr: u16, val: u8) {
        match addr {
            ..0x2000 => this.mapper.write_chr(addr, val),
            ..0x3f00 => {
                let normalized = if addr >= 0x3000 { addr - 0x1000 } else { addr };
                if this.get_nametable_addr(normalized) is ?nametable {
                    this.ram[nametable + (addr & 0x3ff)] = val;
                } else {
                    this.mapper.write_chr(normalized, val);
                }
            }
            ..0x3fff => {
                mut idx = (addr & 0x1f) as! u8;
                if idx >= 0x10 and idx % 4 == 0 {
                    idx &= 0xf;
                }
                this.palette[idx] = val;
            },
            _ => {}
        }
    }

    fn get_nametable_addr(this, addr: u16): ?u16 {
        let nametable = match addr {
            ..0x2400 => 0,
            ..0x2800 => 1,
            ..0x2c00 => 2,
            _ => 3,
        };
        match this.mapper.mirroring() {
            Mirroring::Horizontal => [0u16, 0, 0x400, 0x400][nametable],
            Mirroring::Vertical => [0u16, 0x400, 0, 0x400][nametable],
            Mirroring::FourScreen => null,
            Mirroring::OneScreenA => [0u16; 4][nametable],
            Mirroring::OneScreenB => [0x400u16; 4][nametable],
        }
    }
}

static PALETTE: [Color; 64] = [
    Color::rgb32(0x666666), Color::rgb32(0x002a88), Color::rgb32(0x1412a7), Color::rgb32(0x3b00a4),
    Color::rgb32(0x5c007e), Color::rgb32(0x6e0040), Color::rgb32(0x6c0600), Color::rgb32(0x561d00),
    Color::rgb32(0x333500), Color::rgb32(0x0b4800), Color::rgb32(0x005200), Color::rgb32(0x004f08),
    Color::rgb32(0x00404d), Color::rgb32(0x000000), Color::rgb32(0x000000), Color::rgb32(0x000000),
    Color::rgb32(0xadadad), Color::rgb32(0x155fd9), Color::rgb32(0x4240ff), Color::rgb32(0x7527fe),
    Color::rgb32(0xa01acc), Color::rgb32(0xb71e7b), Color::rgb32(0xb53120), Color::rgb32(0x994e00),
    Color::rgb32(0x6b6d00), Color::rgb32(0x388700), Color::rgb32(0x0c9300), Color::rgb32(0x008f32),
    Color::rgb32(0x007c8d), Color::rgb32(0x000000), Color::rgb32(0x000000), Color::rgb32(0x000000),
    Color::rgb32(0xfffeff), Color::rgb32(0x64b0ff), Color::rgb32(0x9290ff), Color::rgb32(0xc676ff),
    Color::rgb32(0xf36aff), Color::rgb32(0xfe6ecc), Color::rgb32(0xfe8170), Color::rgb32(0xea9e22),
    Color::rgb32(0xbcbe00), Color::rgb32(0x88d800), Color::rgb32(0x5ce430), Color::rgb32(0x45e082),
    Color::rgb32(0x48cdde), Color::rgb32(0x4f4f4f), Color::rgb32(0x000000), Color::rgb32(0x000000),
    Color::rgb32(0xfffeff), Color::rgb32(0xc0dfff), Color::rgb32(0xd3d2ff), Color::rgb32(0xe8c8ff),
    Color::rgb32(0xfbc2ff), Color::rgb32(0xfec4ea), Color::rgb32(0xfeccc5), Color::rgb32(0xf7d8a5),
    Color::rgb32(0xe4e594), Color::rgb32(0xcfef96), Color::rgb32(0xbdf4ab), Color::rgb32(0xb3f3cc),
    Color::rgb32(0xb5ebf2), Color::rgb32(0xb8b8b8), Color::rgb32(0x000000), Color::rgb32(0x000000),
];
