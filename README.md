# fire-vga
A basic implementation of the old fire demo effect for x86-based DOS computers with VGA video cards.

## How to build
You should be able to compile the various fire_*.asm files using any sufficiently old version of MASM.
Development was performed using MASM 4.0

The number after "fire_" in each filename is the number of screen pixels each fire pixel takes up.
I.e. fire_4 has fire pixels that are twice the size of fire_2, and thus runs ~4x faster.
You can build all versions at once by running [buildall.bat](buildall.bat)

## License
This project is licensed under the MIT license.
