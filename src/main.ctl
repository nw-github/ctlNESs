use sdl::*;
use utils::*;
use emu::ipt::*;
use emu::Nes;
use emu::ppu;
use emu::cart::Cart;
use emu::apu::Channel;
use std::time::Instant;

fn read_bytes(path: str): ?[u8] {
    let fp = File::open(path:, mode: "rb")?;
    defer fp.close();

    fp.seek(:End(offset: 0));
    let len = fp.tell() as! uint;
    fp.seek(:Start(offset: 0));
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

fn print_channels([a, b, t, n, d]: [bool; 5]) {
    let ic = ['🔊', '🔇'];
    println("1: {ic[a as u8]} 2: {ic[b as u8]} T: {ic[t as u8]} N: {ic[n as u8]} D: {ic[d as u8]}");
}

fn main() {
    const NAME: str = "ctlNESs";
    const SAMPLE_RATE: uint = 48000;

    let keymap: [Scancode: JoystickBtn] = [
        Scancode::W: JoystickBtn::Up,
        Scancode::A: JoystickBtn::Left,
        Scancode::S: JoystickBtn::Down,
        Scancode::D: JoystickBtn::Right,
        Scancode::O: JoystickBtn::B,
        Scancode::I: JoystickBtn::A,
        Scancode::U: JoystickBtn::A,
        Scancode::Return: JoystickBtn::Start,
        Scancode::Tab: JoystickBtn::Select,
    ];
    let channel_hotkeys: [Scancode: Channel] = [
        Scancode::Num6: Channel::Pulse1,
        Scancode::Num7: Channel::Pulse2,
        Scancode::Num8: Channel::Triangle,
        Scancode::Num9: Channel::Noise,
        Scancode::Num0: Channel::Dmc,
    ];

    mut file: ?str = null;
    mut vsync = false;
    mut scale = 3u32;

    let args: [str] = std::env::args().collect();
    mut i = 0u;
    while args.get(i++) is ?arg {
        match *arg {
            "-v" | "--vsync" => vsync = true,
            "-s" | "--scale" => {
                guard args.get(i++) is ?next else {
                    std::proc::fatal("argument -s requires a scale");
                }

                scale = u32::from_str_radix(*next, 10) ?? {
                    std::proc::fatal("couldn't parse invalid scale '{next}'");
                };
            }
            arg => file = arg,
        }
    }

    guard file is ?path else {
        std::proc::fatal("usage: {args[0]} [-v|--vsync] [-s|--scale SCALE] <file>");
    }

    guard read_bytes(path) is ?data else {
        std::proc::fatal("couldn't read input file '{path}'");
    }

    guard Cart::new(data[..]) is ?cart else {
        std::proc::fatal("invalid cartridge file");
    }
    eprintln("vsync {vsync then "enabled" else "disabled"}");
    eprintln("mapper: {cart.mapper}");
    eprintln("has battery: {cart.has_battery}");
    eprintln("mirroring: {cart.mirroring as u8}");
    eprintln("chr_rom: {cart.chr_rom.len():#x}");
    eprintln("prg_rom: {cart.prg_rom.len():#x}");

    let save_path = "{path}.nsav".to_str();
    let save = if cart.has_battery and read_bytes(save_path) is ?save {
        eprintln("Loaded {save.len()} byte save from '{save_path}'");
        save[..]
    };
    mut nes = Nes::new(cart, InputMode::Nes, save);
    guard Audio::new(sample_rate: SAMPLE_RATE) is ?mut audio else {
        std::proc::fatal("Error occurred while initializing SDL Audio: {sdl::get_last_error()}");
    }
    defer audio.deinit();

    guard Window::new(
        title: NAME,
        width: ppu::HPIXELS as! u32,
        height: ppu::VPIXELS as! u32,
        scale:,
        vsync:,
    ) is ?mut wnd else {
        std::proc::fatal("Error occurred while initializing SDL Window: {sdl::get_last_error()}");
    }
    defer wnd.deinit();

    audio.unpause();
    mut mixer = audio::Mixer::new(SAMPLE_RATE as f64);

    mut fps_clock = Instant::now();
    mut fps_history = [60.0; 20];
    mut fpsi = 0u;
    mut nes_frame = 1u;
    mut time = 0.0;
    mut clock = Instant::now();
    mut speed = 2.0;
    mut modify_speed = false;
    mut channels = [false; 5];
    @outer: loop {
        fps_history[fpsi++ % fps_history.len()] = fps_clock.restart().as_secs();
        if nes_frame % 60 == 0 {
            mut fps = 0.0;
            for v in fps_history.iter() {
                fps += *v;
            }
            fps /= fps_history.len() as f64;
            wnd.set_title("{NAME} ({(1.0 / fps * 100.0).floor() / 100.0} FPS)");
        }

        wnd.clear(Color::rgb(0, 0, 0));

        while wnd.poll_event() is ?event {
            match event {
                :Quit => break @outer,
                :Window({event}) => {
                    if event is :Close {
                        break @outer;
                    }
                }
                :KeyDown(event) => {
                    if keymap.get(&event.scancode) is ?btn {
                        nes.input().press(*btn, 0);
                        nes.input().press(*btn, 1);
                    } else if channel_hotkeys.get(&event.scancode) is ?channel {
                        channels[*channel as u8] = nes.toggle_channel_mute(*channel);
                        print_channels(channels);
                    }
                    match event.scancode {
                        :R => {
                            if event.modifiers & (0x40 | 0x80) != 0 {
                                nes = Nes::new(
                                    cart,
                                    nes.input().mode,
                                    cart.has_battery.then_some(nes.sram()),
                                );
                                println("executed hard reset");
                            } else {
                                nes.reset();
                                println("executed soft reset");
                            }
                        }
                        :Num1 => modify_speed = true,
                        :Num2 => {
                            speed = 0.125.max(speed / 2.0);
                            println("set speed to {speed}x");
                        }
                        :Num3 => {
                            speed = 8.0.min(speed * 2.0);
                            println("set speed to {speed}x");
                        }
                        :Num4 => {
                            match nes.input().mode {
                                :AllowOpposing => {
                                    nes.input().mode = :Keyboard;
                                    println("set input mode to keyboard");
                                }
                                :Keyboard => {
                                    nes.input().mode = :Nes;
                                    println("set input mode to nes");
                                }
                                :Nes => {
                                    nes.input().mode = :AllowOpposing;
                                    println("set input mode to allow opposing");
                                }
                            }
                        }
                        _ => {}
                    }
                }
                :KeyUp(event) => {
                    if keymap.get(&event.scancode) is ?btn {
                        nes.input().release(*btn, 0);
                        nes.input().release(*btn, 1);
                    } else if event.scancode is :Num1 {
                        modify_speed = false;
                    }
                }
            }
        }

        time += clock.restart().as_secs();

        let frametime = 1.0 / 60.0 / (modify_speed.then_some(speed) ?? 1.0);
        if time >= frametime {
            nes_frame++;
            time -= frametime;
            while !nes.cycle() {}

            mixer.process(audio.buffer(), nes.audio_buffer(), null);
            wnd.draw_scaled(nes.video_buffer());
        }

        wnd.present();
    }

    if cart.has_battery {
        eprintln("Saved prg_ram to '{save_path}'");
        write_bytes(save_path, nes.sram());
    }
}
