use ctlness::utils::ReadExt;
pub use super::ppu::Mirroring;

pub struct Cart {
    pub chr_rom: [u8..],
    pub prg_rom: [u8..],
    pub mirroring: Mirroring,
    pub has_battery: bool,
    pub mapper: u8,

    pub fn new(mut data: [u8..]): ?This {
        guard data.read_exact(4) is ?[b'N', b'E', b'S', b'\x1a'] else {
            return null;
        }

        let prg_pages = data.read_u8()?;
        let chr_pages = data.read_u8()?;
        let flags6 = data.read_u8()?;
        let flags7 = data.read_u8()?;
        data.read_exact(8)?;
        if flags6 & 4 != 0 {
            eprintln("cartridge has trainer present, ignoring it");
            data.read_exact(512);
        }
        Cart(
            mirroring: if flags6 & 8 != 0 {
                :FourScreen
            } else {
                match flags6 & 1 != 0 {
                    false => :Horizontal,
                    true => :Vertical,
                }
            },
            has_battery: flags6 & 2 != 0,
            mapper: (flags6 >> 4) + (flags7 & 0xf0),
            prg_rom: data.read_exact(0x4000 * prg_pages as uint)?,
            chr_rom: data.read_exact(0x2000 * chr_pages as uint)?,
        )
    }
}
