; The number of bits to shift the fire increment. Increase to improve performance at the cost of resolution.
; WARNING: Values above 4 will result in incomplete screen fill (VGA is 320x200, 200 / 16 = 12.5, since this is fractional it will be truncated and pixels will be missed.)
; WARNING: This value must not be greater than 7!
FIRE_PIXEL_SIZE_SHIFT equ 3

INCLUDE main.asm
