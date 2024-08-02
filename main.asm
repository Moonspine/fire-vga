; Fire VGA Main Program
; Old school fire effect for VGA video cards
; Copyright (c) 2024 Moonspine
; Available for use under the MIT license

.8086

; The number of bits to shift the fire increment. Increase to improve performance at the cost of resolution.
; WARNING: Values above 4 will result in incomplete screen fill (VGA is 320x200, 200 / 16 = 12.5, since this is fractional it will be truncated and pixels will be missed.)
; WARNING: This value must not be greater than 7!
; WARNING: This is commented out because it is defined in fire_*.asm
;          Assembly should begin at those files rather than this one.
;FIRE_PIXEL_SIZE_SHIFT equ 0

FIRE_PIXEL_RUN_LENGTH equ (1 shl FIRE_PIXEL_SIZE_SHIFT)

VGA_SCREEN_WIDTH equ 320
VGA_SCREEN_HEIGHT equ 200

FLAME_BUFFER_WIDTH equ (VGA_SCREEN_WIDTH shr FIRE_PIXEL_SIZE_SHIFT)
FLAME_BUFFER_HEIGHT equ (VGA_SCREEN_HEIGHT shr FIRE_PIXEL_SIZE_SHIFT)
FLAME_BUFFER_SIZE equ (FLAME_BUFFER_WIDTH * FLAME_BUFFER_HEIGHT)

SEED_PADDING equ 16

DATA segment
	flameBuffer db FLAME_BUFFER_SIZE dup(?)
INCLUDE data\palette.asm
	paletteEnd db 0
	rng dw 4242h
DATA ends

CODE segment
	 assume cs:CODE, ds:DATA
	 
; DOS includes
INCLUDE dos\misc.asm

; Main program
START:
	; Set the main data segment
	mov dx, SEG DATA
	mov ds, dx
	
	; Enter VGA mode 0x13
	mov ax, 0013h
	int 10h
	
	; Load palette
	call LoadPalette
	
	; Render fire
FireLoop:
	; Update the flame effect
	call UpdateFire
	
	; Waits for vertical retrace before copying pixels
	call WaitForVSync
	
	; Copy the fire pixels to video memory
	call CopyFirePixels
	
	; If the user presses a key, exit the loop
	mov ah, 01h
	int 16h
	je FireLoop
	
	
	; Return to text mode
	mov ax, 0003h
	int 10h

	call exitToDOS




LoadPalette PROC
	; Set the main data segment
	mov dx, SEG DATA
	mov ds, dx

	; Start at palette address 0
	mov dx, 3C8h
	mov al, 0h
	out dx, al
	
	; Write all palette entries
	mov di, OFFSET palette
	mov dx, 3C9h
LoadPalette_Loop:
	; Red
	mov al, [ds:di]
	out dx, al
	inc di
	
	; Green
	mov al, [ds:di]
	out dx, al
	inc di
	
	; Blue
	mov al, [ds:di]
	out dx, al
	inc di
	
	; Loop?
	cmp di, OFFSET paletteEnd
	jne LoadPalette_Loop

	ret
LoadPalette ENDP



UpdateFire PROC
	; Prepare flame buffer segment
	mov di, SEG flameBuffer
	mov ds, di
	
	; Load buffer size
	; cx = width
	mov cx, FLAME_BUFFER_WIDTH
	
	; Prepare row pointers
	; bx = writing row
	; di = reading row
	mov bx, OFFSET flameBuffer
	mov di, (OFFSET flameBuffer) + FLAME_BUFFER_WIDTH
	
	mov ax, FLAME_BUFFER_HEIGHT - 1
UpdateFire_Loop:
	; Update the current row
	call UpdateFireRow
	
	; Continue to the next row
	dec ax
	jne UpdateFire_Loop

	; Seed the last fire row
	call SeedFire
	
	ret
UpdateFire ENDP



; Averages a pixel value
AveragePixel MACRO
	mov dl, 3
	div dl
ENDM



; Subtracts FIRE_PIXEL_RUN_LENGTH from the value in ax, clamping at zero
DarkenPixel MACRO
	local DarkenPixel_FinishDarken
	
	sub al, FIRE_PIXEL_RUN_LENGTH
	jnc DarkenPixel_FinishDarken
	mov al, 0
	
DarkenPixel_FinishDarken:
ENDM



; Updates the fire row.
; Upon entry, the following is assumed:
; ds = segment of flameBuffer
; di = offset of the first element in the reading row
; bx = offset of the first element in the writing row
; cx = fire width
; ax and cx are preserved by this proc
; di and bx are incremented to the start of their next respective rows after this proc finishes
UpdateFireRow PROC
	push ax
	push cx

	mov si, cx
	
	; The first pixel is a special case
	; Sum the pixel
	mov dh, 0
	
	mov cl, [ds:di]
	inc di
	mov ch, [ds:di]
	inc di
	
	mov dl, cl
	mov ax, dx
	mov dl, ch
	add ax, dx
	
	; Average pixel and darken
	AveragePixel
	DarkenPixel
	
	; Write the pixel and move to the next
	mov [ds:bx], al
	inc bx
	
	
	dec si
	dec si
UpdateFireRow_Loop:
	; Add the previous two pixels
	mov dl, cl
	mov ax, dx
	mov dl, ch
	add ax, dx
	
	; Replace the oldest pixel with a new one
	mov cl, ch
	mov ch, [ds:di]
	inc di
	
	; Add the new pixel
	mov dl, ch
	add ax, dx
	
	; Average pixel and darken
	AveragePixel
	DarkenPixel
	
	; Write the pixel and move to the next
	mov [ds:bx], al
	inc bx

	; Loop?
	dec si
	jne UpdateFireRow_Loop
	
	; The last pixel is also a special case
	; Add the previous two pixels
	mov dl, cl
	mov ax, dx
	mov dl, ch
	add ax, dx
	
	; Average pixel and darken
	AveragePixel
	DarkenPixel
	
	; Write the pixel and move to the next
	mov [ds:bx], al
	inc bx
	

	pop cx
	pop ax
	ret
UpdateFireRow ENDP


; Seeds the last fire row.
; Upon entry, the following is assumed:
; ds = segment of flameBuffer
; bx = offset of the first element in the seed row
; cx = fire width
SeedFire PROC
	; Just give a little breathing room on the sides
	sub cx, SEED_PADDING shr FIRE_PIXEL_SIZE_SHIFT
	add bx, (SEED_PADDING shr FIRE_PIXEL_SIZE_SHIFT) / 2
	
	mov ax, rng
SeedFire_Loop:
	; Check RNG
	call UpdateRNG
	cmp ax, 08000h
	jb SeedFire_Zero
	
	; Seed with 1
	mov dl, 0ffh
	mov [ds:bx], dl
	
	jmp SeedFire_Continue
	
	; Seed with 0
SeedFire_Zero:
	mov dl, 0
	mov [ds:bx], dl

SeedFire_Continue:
	inc bx
	
	; Loop until finished
	dec cx
	jne SeedFire_Loop
	
	mov rng, ax

	ret
SeedFire ENDP



; Updates the RNG value using a 16-bit LFSR
; Before calling, the RNG value to update should be in ax
; After calling, the new RNg value is in ax
UpdateRNG PROC
	push bx
	push cx
	
	mov bx, ax
	and bx, 1
	mov cx, ax
REPT 2
	shr cx, 1
ENDM
	and cx, 1
	xor bx, cx
	
	mov cx, ax
REPT 3
	shr cx, 1
ENDM
	and cx, 1
	xor bx, cx
	
	mov cx, ax
REPT 5
	shr cx, 1
ENDM
	and cx, 1
	xor bx, cx
	
REPT 15
	shl bx, 1
ENDM
	shr ax, 1
	or ax, bx
	
	pop cx
	pop bx

	ret
UpdateRNG ENDP



WaitForVSync PROC
	mov dx, 03DAh

WaitForVSync_Loop:
	in al, dx
	test al, 1000b
	jz WaitForVSync_Loop

	ret
WaitForVSync ENDP


; Copies fire pixels from the flame buffer to the screen
CopyFirePixels PROC
	mov di, 0
	mov bx, OFFSET flameBuffer

	mov dx, FLAME_BUFFER_WIDTH
CopyFirePixels_Loop:
	mov si, SEG flameBuffer
	mov ds, si
	mov cl, [ds:bx]
	mov si, 0A000h
	mov ds, si
	
	
	; Repeat block
	mov al, FIRE_PIXEL_RUN_LENGTH
CopyFirePixels_RepeatBlockVertical:
	mov ah, FIRE_PIXEL_RUN_LENGTH
CopyFirePixels_RepeatBlockHorizontal:
	mov [ds:di], cl
	inc di
	
	dec ah
	jne CopyFirePixels_RepeatBlockHorizontal
	
	; Repeat vertically
	add di, VGA_SCREEN_WIDTH - FIRE_PIXEL_RUN_LENGTH
	dec al
	jne CopyFirePixels_RepeatBlockVertical
	
	; Next pixel
	inc bx
	
	; Is it in the same row?
	dec dx
	je CopyFirePixels_NextRow
	
	; If so, go back to the first pixel of the next block
	sub di, VGA_SCREEN_WIDTH * FIRE_PIXEL_RUN_LENGTH - FIRE_PIXEL_RUN_LENGTH
	jmp CopyFirePixels_ContinueLoop
	
	; If not, go to the next row
CopyFirePixels_NextRow:
	mov dx, FLAME_BUFFER_WIDTH
	sub di, VGA_SCREEN_WIDTH - FIRE_PIXEL_RUN_LENGTH

CopyFirePixels_ContinueLoop:
	cmp bx, FLAME_BUFFER_SIZE
	jb CopyFirePixels_Loop
	
	ret
CopyFirePixels ENDP



CODE ends

STACK segment stack
	 assume ss:STACK
	 dw 64 dup(?)
STACK ends

end START
