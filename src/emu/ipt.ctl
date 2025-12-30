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
    pub mode: InputMode,
    raw_state: [u8; 2] = [0; 2],
    real: [u8; 2] = [0; 2],
    poll_input: [u8; 2] = [0; 2],

    pub fn new(mode: InputMode): This => Input(mode:);

    pub fn press(mut this, btn: JoystickBtn, controller: u1) {
        this.raw_state[controller] |= 1 << btn as u32;
        this.real[controller] |= 1 << btn as u32;
        if !(this.mode is InputMode::AllowOpposing) {
            this.raw_state[controller] &= !(1 << match btn {
                JoystickBtn::Left => JoystickBtn::Right as u32,
                JoystickBtn::Right => JoystickBtn::Left as u32,
                JoystickBtn::Up => JoystickBtn::Down as u32,
                JoystickBtn::Down => JoystickBtn::Up as u32,
                _ => return,
            });
        }
    }

    pub fn release(mut this, btn: JoystickBtn, controller: u1) {
        this.raw_state[controller] &= !(1 << btn as u32);
        this.real[controller] &= !(1 << btn as u32);
        if this.mode is InputMode::Keyboard {
            this.raw_state[controller] |= this.real[controller] & (1 << match btn {
                JoystickBtn::Left => JoystickBtn::Right as u32,
                JoystickBtn::Right => JoystickBtn::Left as u32,
                JoystickBtn::Up => JoystickBtn::Down as u32,
                JoystickBtn::Down => JoystickBtn::Up as u32,
                _ => return,
            });
        }
    }

    impl super::bus::Mem {
        fn peek(this, addr: u16): ?u8 {
            match addr {
                0x4016 => this.poll_input[0] & 1,
                0x4017 => this.poll_input[1] & 1,
                _ => null,
            }
        }

        fn read(mut this, addr: u16): ?u8 {
            // TODO: upper 4 bits should be open bus?
            match addr {
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
                _ => null,
            }
        }

        fn write(mut this, _: *mut super::bus::Bus, addr: u16, val: u8) {
            if addr == 0x4016 and val & 1 != 0 {
                this.poll_input = this.raw_state;
            }
        }
    }
}
