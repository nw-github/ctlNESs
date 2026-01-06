use super::bus::*;
use ctlness::sdl::Color;

pub union Mirroring {
    Horizontal,
    Vertical,
    FourScreen,
    OneScreenA,
    OneScreenB,
}

pub const HPIXELS: uint = 256;
pub const VPIXELS: uint = 240;

const SCANLINE_END_CYCLE: u16 = 340;

packed struct Ctrl {
    nametable_select: u2 = 0,
    inc: bool = false,
    spr_tile_addr: bool = false,
    bg_tile_addr: bool = false,
    long_sprites: bool = false,
    master_slave: bool = false,
    nmi_enable: bool = false,

    pub fn increment(this): u16 => this.inc then 32 else 1;
    pub fn from_u8(val: u8): This => unsafe std::mem::bit_cast(val);
}

packed struct Mask {
    greyscale: bool = false,
    show_bg_l8: bool = false,
    show_sprites_l8: bool = false,
    show_bg: bool = true,
    show_sprites: bool = true,
    emphasize_red: bool = false,
    emphasize_green: bool = false,
    emphasize_blue: bool = false,

    pub fn from_u8(val: u8): This => unsafe std::mem::bit_cast(val);
}

union State {
    PreRender,
    Render,
    PostRender,
    VBlank,
}

@(layout(C))
struct Sprite {
    y: u8 = 0,
    tile: u8 = 0,
    attr: u8 = 0,
    x: u8 = 0,
}

pub struct Ppu {
    mapper: *dyn mut Mapper,
    dma_flag: *mut bool,
    palette: [u8; 0x20] = [0; 0x20],
    ram: [u8; 0x800] = [0; 0x800],
    oam: [Sprite; 64] = [Sprite(); 64],
    sprites: [u8; 8] = [0; 8],
    sprite_count: uint = 0,

    state: State = :PreRender,
    cycle: u16 = 0,
    scanline: u16 = 0,
    even_frame: bool = true,
    vblank: bool = false,
    spr_zero_hit: bool = false,
    spr_overflow: bool = false,

    ctrl: Ctrl = Ctrl(),
    mask: Mask = Mask(),
    v: u16 = 0,      // scroll position while rendering, vram addr otherwise
    t: u16 = 0,      // starting coarse x scroll and starting y scroll while rendering,
                     // scroll/tmp vram addr otherwise
    x: u8 = 0,       // fine x position for current scroll
    w: bool = false, // write latch for ppuscroll/ppuaddr
    oam_addr: u8 = 0,
    data_buf: u8 = 0,

    pub fn new(mapper: *dyn mut Mapper, dma_flag: *mut bool): This => Ppu(mapper:, dma_flag:);

    pub fn reset(mut this) {
        this.cycle = 0;
        this.even_frame = true;
        this.scanline = 0;
        this.data_buf = 0;
        this.ctrl = Ctrl::from_u8(0);
        this.mask = Mask::from_u8(0);
        this.w = false;
    }

    pub fn step(mut this, buf: [mut u32..], nmi: *mut bool): bool {
        mut result = false;
        match this.state {
            :PreRender => {
                let rendering_on = this.mask.show_bg and this.mask.show_sprites;
                if this.cycle == HPIXELS as! u16 + 2 and rendering_on {
                    this.v = (this.v & !0x41f) | (this.t & 0x41f);
                } else if this.cycle is 281..=304 and rendering_on {
                    this.v = (this.v & !0x7be0) | (this.t & 0x7be0);
                }

                if this.cycle >= SCANLINE_END_CYCLE - (!this.even_frame and rendering_on) as u16 {
                    this.state = :Render;
                    this.cycle = 0;
                    this.scanline = 0;
                }

                if this.cycle == 260 and rendering_on {
                    this.mapper.scanline();
                }
            }
            :Render => this.render(buf),
            :PostRender => {
                if this.cycle >= SCANLINE_END_CYCLE {
                    this.scanline++;
                    this.cycle = 0;
                    this.state = :VBlank;
                    result = true;
                }
            }
            :VBlank => {
                if this.cycle == 1 and this.scanline == VPIXELS as! u16 + 1 {
                    this.vblank = true;
                    if this.ctrl.nmi_enable {
                        *nmi = true;
                    }
                }
                if this.cycle >= SCANLINE_END_CYCLE {
                    this.scanline++;
                    this.cycle = 0;
                }
                if this.scanline >= 261 {
                    this.state = :PreRender;
                    this.scanline = 0;
                    this.even_frame = !this.even_frame;
                    this.vblank = false;
                    this.spr_zero_hit = false;
                }
            }
        }

        this.cycle++;
        result
    }

    fn render(mut this, buf: [mut u32..]) {
        let show_bg = this.mask.show_bg;
        let show_spr = this.mask.show_sprites;
        if (0u16..=HPIXELS as! u16).contains(&this.cycle) {
            mut [bg_color, spr_color] = [0u8; 2];
            mut [bg_opaque, spr_opaque] = [false, true];
            mut spr_foreground = false;
            let [x, y] = [this.cycle - 1, this.scanline];
            if show_bg {
                let x_fine = (this.x as u16 + x) % 8;
                if this.mask.show_bg_l8 or x >= 8 {
                    let tile = this.ppu_read((this.v & 0xfff) | 0x2000) as u16;
                    let addr = (tile * 16 + ((this.v >> 12) & 0x7)) | (this.ctrl.bg_tile_addr as u16 << 12);

                    bg_color = (this.ppu_read(addr) >> (x_fine ^ 7)) & 1;
                    bg_color |= ((this.ppu_read(addr + 8) >> (x_fine ^ 7)) & 1) << 1;
                    bg_opaque = bg_color != 0;

                    let attr = this.ppu_read(
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

            if show_spr and (this.mask.show_sprites_l8 or x >= 8) {
                for i in this.sprites[..this.sprite_count].iter() {
                    let {x: spr_x, y: spr_y, tile, attr} = this.oam[*i];
                    let spr_x = spr_x as u16;
                    if x < spr_x or x - spr_x >= 8 {
                        continue;
                    }

                    let spr_y   = (spr_y + 1) as u16;
                    let tile    = tile as u16;
                    let len     = this.ctrl.long_sprites then 16u16 else 8;
                    mut x_shift = (x - spr_x) % 8;
                    mut y_offs  = (y - spr_y) % len;
                    if attr & 0x40 == 0 {
                        x_shift ^= 7;
                    }
                    if attr & 0x80 != 0 {
                        y_offs ^= len - 1;
                    }

                    let addr = if !this.ctrl.long_sprites {
                        tile * 16 + y_offs + (this.ctrl.spr_tile_addr as u16 << 12)
                    } else {
                        y_offs = (y_offs & 7) | ((y_offs & 8) << 1);
                        ((tile >> 1) * 32 + y_offs) | ((tile & 1) << 12)
                    };

                    spr_color |= (this.ppu_read(addr) >> x_shift) & 1;
                    spr_color |= ((this.ppu_read(addr + 8) >> x_shift) & 1) << 1;
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

            let palette = if (!bg_opaque and spr_opaque) or
                (bg_opaque and spr_opaque and spr_foreground)
            {
                spr_color
            } else if !bg_opaque and !spr_opaque {
                0
            } else {
                bg_color
            };

            mut idx = this.ppu_read(0x3f00 + (palette as u16));
            if idx as uint >= PALETTE.len() {
                // eprintln("attempt to render bad palette index {idx}");
                idx = 0;
            }
            buf[x + y * HPIXELS as! u16] = PALETTE[idx].to_abgr32();
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
            this.mapper.scanline();
        }

        if this.cycle >= SCANLINE_END_CYCLE {
            this.sprite_count = 0;

            let range = this.ctrl.long_sprites then 16u16 else 8;
            for i in this.oam_addr / 4..64 {
                let spr_y = this.oam[i].y as u16;
                if this.scanline >= spr_y and this.scanline - spr_y < range {
                    if this.sprite_count == this.sprites.len() {
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
            this.state = :PostRender;
        }
    }

    // r $2002
    fn read_status(mut this): u8 {
        let status = this.peek_status();
        this.vblank = false;
        this.w = false;
        status
    }

    // r $2002
    fn peek_status(this): u8 {
        // TODO: lower 5 bits should be PPU open bus
        this.vblank as u8 << 7 | this.spr_zero_hit as u8 << 6 | this.spr_overflow as u8 << 5
    }

    // r $2004
    fn read_oam(this): u8 => this.oam_bytes()[this.oam_addr];

    // r $2007
    fn read_data(mut this): u8 {
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
    fn peek_data(this): u8 => this.ppu_read(this.v);

    // w $2000
    fn write_ctrl(mut this, val: u8) {
        this.ctrl = Ctrl::from_u8(val);
        this.t = (this.t & !0xc00) | (this.ctrl.nametable_select as u16 << 10);
    }

    // w $2001
    fn write_mask(mut this, val: u8) {
        this.mask = Mask::from_u8(val);
    }

    // w $2003
    fn write_oam_addr(mut this, val: u8) {
        this.oam_addr = val;
    }

    // w $2004
    fn write_oam(mut this, val: u8) {
        this.oam_bytes_mut()[this.oam_addr++ as uint] = val;
    }

    // w $2005
    fn write_scroll(mut this, val: u8) {
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
    fn write_addr(mut this, val: u8) {
        if !this.w {
            this.t = (this.t & !0xff00) | ((val as u16 & 0x3f) << 8);
        } else {
            this.t = (this.t & !0xff) | val as u16;
            this.v = this.t;
        }
        this.w = !this.w;
    }

    // w $2007
    fn write_data(mut this, val: u8) {
        this.ppu_write(this.v, val);
        this.v += this.ctrl.increment();
    }

    // w $4014
    fn write_oam_dma(mut this, idx: u8, val: u8) {
        this.oam_bytes_mut()[this.oam_addr.wrapping_add(idx) as uint] = val;
    }

    fn ppu_read(this, addr: u16): u8 {
        match addr {
            ..0x2000 => this.mapper.read_chr(addr),
            ..0x3f00 => {
                let normalized = addr >= 0x3000 then addr - 0x1000 else addr;
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

    fn ppu_write(mut this, addr: u16, val: u8) {
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
            :Horizontal => nametable < 2 then 0 else 0x400,
            :Vertical => nametable & 1 == 0 then 0 else 0x400,
            :FourScreen => null,
            :OneScreenA => 0,
            :OneScreenB => 0x400,
        }
    }

    fn oam_bytes(this): [u8..] {
        unsafe std::span::Span::new(
            this.oam.as_raw().cast(),
            this.oam.len() * std::mem::size_of::<Sprite>(),
        )
    }

    fn oam_bytes_mut(mut this): [mut u8..] {
        unsafe std::span::SpanMut::new(
            this.oam.as_raw_mut().cast(),
            this.oam.len() * std::mem::size_of::<Sprite>(),
        )
    }

    impl Mem {
        fn peek(this, addr: u16): ?u8 {
            if addr is 0x2000..0x4000 {
                match addr & 0x2007 {
                    0x2002 => this.peek_status(),
                    0x2004 => this.read_oam(),
                    0x2007 => this.peek_data(),
                    _ => return null,
                }
            }
        }

        fn read(mut this, addr: u16): ?u8 {
            if addr is 0x2000..0x4000 {
                match addr & 0x2007 {
                    0x2002 => this.read_status(),
                    0x2004 => this.read_oam(),
                    0x2007 => this.read_data(),
                    _ => return null,
                }
            }
        }

        fn write(mut this, bus: *mut Bus, addr: u16, val: u8) {
            match addr {
                0x2000..0x4000 => match addr & 0x2007 {
                    0x2000 => this.write_ctrl(val),
                    0x2001 => this.write_mask(val),
                    0x2003 => this.write_oam_addr(val),
                    0x2004 => this.write_oam(val),
                    0x2005 => this.write_scroll(val),
                    0x2006 => this.write_addr(val),
                    0x2007 => this.write_data(val),
                    _ => {}
                }
                0x4014 => {
                    for i in 0u8..=255 {
                        this.write_oam_dma(i, bus.read((val as u16 << 8).wrapping_add(i as u16)));
                    }
                    *this.dma_flag = true;
                }
                _ => {}
            }
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
