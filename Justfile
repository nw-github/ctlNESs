play CMD:
    ~/.cache/cargo-target/release/ctl r -qo -lSDL2 -lm . -- "{{CMD}}" -s 4

dump:
    ~/.cache/cargo-target/release/ctl p -qp . main.c
