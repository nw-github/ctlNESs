use sdl::*;
use utils::*;
use emu::*;
use emu::cart::Cartridge;
use emu::apu::Channel;

struct Timespec {
    tv_sec: c_long,
    tv_nsec: c_long,

    pub fn -(this, rhs: *Timespec): Timespec {
        mut tv_nsec = this.tv_nsec - rhs.tv_nsec;
        mut tv_sec  = this.tv_sec - rhs.tv_sec;
        if tv_sec > 0 and tv_nsec < 0 {
            tv_nsec += 1000000000;
            tv_sec--;
        } else if tv_sec < 0 and tv_nsec > 0 {
            tv_nsec -= 1000000000;
            tv_sec++;
        }
        Timespec(tv_sec:, tv_nsec:)
    }

    pub fn now(): This {
        import fn clock_gettime(clockid: c_int, tp: *mut Timespec): c_int;

        mut tp = Timespec(tv_sec: 0, tv_nsec: 0);
        clock_gettime(1, &mut tp);
        tp
    }

    pub fn as_nanos(this): u64 {
        this.tv_nsec as u64 + this.tv_sec as u64 * 1000000000
    }

    pub fn as_millis(this): u64 {
        this.tv_nsec as u64 / 1000000 + this.tv_sec as u64 * 1000
    }

    pub fn as_seconds(this): f64 {
        this.tv_sec as! f64 + (this.tv_nsec as! f64 / 1000000000.0)
    }
}

pub struct Clock {
    last: Timespec,

    pub fn new(): Clock {
        Clock(last: Timespec::now())
    }

    pub fn elapsed(this): Timespec {
        Timespec::now() - this.last
    }

    pub fn restart(mut this): Timespec {
        let elapsed = this.elapsed();
        this.last = Timespec::now();
        elapsed
    }
}

fn read_bytes(path: str): ?[u8] {
    let fp = File::open(path:, mode: "rb")?;
    defer fp.close();

    fp.seek(SeekPos::End(offset: 0));
    let len = fp.tell() as! uint;
    fp.seek(SeekPos::Start(offset: 0));
    mut buf = @[0u8; len];
    if fp.read(buf[..]) != len {
        return null;
    }
    buf
}

fn write_bytes(path: str, bytes: [u8..]): bool {
    guard File::open(path:, mode: "wb") is ?fp else {
        return false;
    }
    defer fp.close();

    fp.write(bytes) == bytes.len()
}

fn print_channels([a, b, t, n, d]: *[bool; 5]) {
    let icons = ['🔊', '🔇'];
    println("1: {
        icons[*a as u8]} 2: {
        icons[*b as u8]} T: {
        icons[*t as u8]} N: {
        icons[*n as u8]} D: {
        icons[*d as u8]}");
}

fn main(args: [str..]): c_int {
    static NAME: str = "ctlNESs";
    static SCALE: i32 = 3;
    static KEYMAP: [Scancode: JoystickBtn] = [
        Scancode::W: JoystickBtn::Up,
        Scancode::A: JoystickBtn::Left,
        Scancode::S: JoystickBtn::Down,
        Scancode::D: JoystickBtn::Right,
        Scancode::I: JoystickBtn::B,
        Scancode::O: JoystickBtn::A,
        Scancode::Return: JoystickBtn::Start,
        Scancode::Tab: JoystickBtn::Select,
    ];
    static CHANNELS: [Scancode: Channel] = [
        Scancode::Num6: Channel::Pulse1,
        Scancode::Num7: Channel::Pulse2,
        Scancode::Num8: Channel::Triangle,
        Scancode::Num9: Channel::Noise,
        Scancode::Num0: Channel::Dmc,
    ];

    guard args.get(1) is ?path else {
        eprintln("usage: {args[0]} <file>");
        return 1;
    }
    let save_path = path + ".nsav";
    guard read_bytes(*path) is ?data else {
        eprintln("couldn't read input file '{path}'");
        return 1;
    }
    guard Cartridge::new(data[..]) is ?cart else {
        eprintln("invalid cartridge file");
        return 1;
    }
    let save = if cart.has_battery and read_bytes(save_path) is ?save {
        eprintln("Loaded {save.len()} byte save from '{save_path}'");
        save[..]
    };
    mut nes = Nes::new(Input::new(InputMode::Keyboard), cart, save);
    guard Audio::new() is ?mut audio else {
        eprintln("Error occurred while initializing SDL Audio: {sdl::get_last_error()}");
        return 1;
    }
    defer audio.deinit();
    guard Window::new(NAME, ppu::HPIXELS as! i32, ppu::VPIXELS as! i32, SCALE) is ?mut wnd else {
        eprintln("Error occurred while initializing SDL Window: {sdl::get_last_error()}");
        return 1;
    }
    defer wnd.deinit();

    audio.unpause();

    mut fps_clock = Clock::new();
    mut fps_history = [60.0; 20];
    mut fpsi = 0u;

    mut time = 0.0;
    mut clock = Clock::new();
    mut done = false;
    mut speed = 2.0;
    mut modify_speed = false;
    mut channels = [false; 5];
    while !done {
        while wnd.poll_event() is ?event {
            match event {
                SdlEvent::Quit => {
                    done = true;
                    break;
                }
                SdlEvent::KeyDown(event) => {
                    if KEYMAP.get(&event.scancode) is ?btn {
                        nes.input().press(*btn, 0);
                        nes.input().press(*btn, 1);
                    } else if CHANNELS.get(&event.scancode) is ?channel {
                        channels[*channel as u8] = nes.toggle_channel_mute(*channel);
                        print_channels(&channels);
                    }
                    match event.scancode {
                        Scancode::R => nes.reset(),
                        Scancode::Num1 => modify_speed = true,
                        Scancode::Num2 => {
                            speed = 0.125.max(speed / 2.0);
                            println("set speed to {speed}x");
                        }
                        Scancode::Num3 => {
                            speed = 8.0.min(speed * 2.0);
                            println("set speed to {speed}x");
                        }
                        Scancode::Num4 => {
                            match nes.input().mode() {
                                InputMode::AllowOpposing => {
                                    nes.input().set_mode(InputMode::Keyboard);
                                    println("set input mode to keyboard");
                                }
                                InputMode::Keyboard => {
                                    nes.input().set_mode(InputMode::Nes);
                                    println("set input mode to nes");
                                }
                                InputMode::Nes => {
                                    nes.input().set_mode(InputMode::AllowOpposing);
                                    println("set input mode to allow opposing");
                                }
                            }
                        }
                        _ => {}
                    }
                }
                SdlEvent::KeyUp(event) => {
                    if KEYMAP.get(&event.scancode) is ?btn {
                        nes.input().release(*btn, 0);
                        nes.input().release(*btn, 1);
                    }
                    match event.scancode {
                        Scancode::Num1 => modify_speed = false,
                        _ => {}
                    }
                }
                SdlEvent::Window({event}) => {
                    if event is WindowEvent::Close {
                        done = true;
                        break;
                    }
                }
            }
        }

        time += clock.restart().as_seconds();
        if time < 1.0 / 60.0 {
            continue;
        }

        time -= 1.0 / 60.0;
        while !nes.cycle() {}

        fps_history[fpsi++ % 20] = fps_clock.restart().as_seconds();
        if fpsi % 60 == 0 {
            mut fps = 0.0;
            for v in fps_history[..].iter() {
                fps += *v;
            }
            let fps = fps / fps_history[..].len() as! f64;
            wnd.set_title("{NAME} ({(1.0 / fps * 100.0).floor() / 100.0} FPS)");
        }

        audio.write(nes.audio_buffer());
        // NTSC skips first 8 scanlines
        wnd.draw_scaled(nes.video_buffer()[8u * 256..]);
    }

    if cart.has_battery {
        eprintln("Saved prg_ram to '{save_path}'");
        write_bytes(save_path, nes.sram());
    }

    0
}
