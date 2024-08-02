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
	flameBuffer db 64000 dup(?)
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
	; dx = height
	mov cx, FLAME_BUFFER_WIDTH
	mov dx, FLAME_BUFFER_HEIGHT
	
	; Prepare row pointers
	; bx = writing row
	; di = reading row
	mov bx, OFFSET flameBuffer
	mov di, bx
	add di, cx
	
	mov ax, dx
	sub ax, 1
UpdateFire_Loop:
	; Update the current row
	call UpdateFireRow
	
	; Continue to the next row
	dec ax
	cmp ax, 0
	jne UpdateFire_Loop

	; Seed the last fire row
	call SeedFire
	
	ret
UpdateFire ENDP



; Averages a pixel value
AveragePixel MACRO
	mov dl, 3
	div dl
	mov ah, 0
ENDM



; Subtracts 1 from the value in ax if ax >= 1
DarkenPixel PROC
	cmp ax, FIRE_PIXEL_RUN_LENGTH
	jb DarkenPixel_SetToZero
	
	sub ax, FIRE_PIXEL_RUN_LENGTH
	jmp DarkenPixel_SkipDarken
	
DarkenPixel_SetToZero:
	mov ax, 0
	
DarkenPixel_SkipDarken:
	ret
DarkenPixel ENDP



; Updates the fire row.
; Upon entry, the following is assumed:
; ds = segment of flameBuffer
; di = offset of the first element in the reading row
; bx = offset of the first element in the writing row
; cx = fire width
; ax, cx, and dx are preserved by this proc
; di and bx are incremented to the start of their next respective rows after this proc finishes
UpdateFireRow PROC
	push ax
	push cx
	push dx

	; The first pixel is a special case
	; Sum the pixel
	mov ax, 0
	mov dh, 0
	mov dl, [ds:di]
	add ax, dx
	inc di
	mov dl, [ds:di]
	add ax, dx
	dec di
	
	; Average pixel and darken
	AveragePixel
	call DarkenPixel
	
	; Write the pixel and move to the next
	mov [ds:bx], ax
	inc bx
	
	
	dec cx
UpdateFireRow_Loop:
	; Sum the pixel data
	mov ax, 0
	mov dh, 0
	mov dl, [ds:di]
	add ax, dx
	inc di
	mov dl, [ds:di]
	add ax, dx
	inc di
	mov dl, [ds:di]
	add ax, dx
	dec di
	
	; Average pixel and darken
	AveragePixel
	call DarkenPixel
	
	; Write the pixel and move to the next
	mov [ds:bx], ax
	inc bx

	; Loop?
	dec cx
	cmp cx, 1
	jne UpdateFireRow_Loop
	
	; The last pixel is also a special case
	; Sum the pixel
	mov ax, 0
	mov dh, 0
	mov dl, [ds:di]
	add ax, dx
	inc di
	mov dl, [ds:di]
	add ax, dx
	inc di
	
	; Average pixel and darken
	AveragePixel
	call DarkenPixel
	
	; Write the pixel and move to the next
	mov [ds:bx], ax
	inc bx
	

	pop dx
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
	
	mov di, OFFSET rng
SeedFire_Loop:
	; Check RNG
	call UpdateRNG
	mov ax, [ds:di]
	cmp ax, 08000h
	jb SeedFire_Zero
	
	; Seed with 1
	mov al, 0ffh
	mov [ds:bx], al
	
	jmp SeedFire_Continue
	
	; Seed with 0
SeedFire_Zero:
	mov al, 0
	mov [ds:bx], al

SeedFire_Continue:
	inc bx
	
	; Loop until finished
	dec cx
	cmp cx, 0
	jne SeedFire_Loop

	ret
SeedFire ENDP



; Updates the RNG value using a 16-bit LFSR
; Upon entry, the following is assumed:
; ds = segment of rng
; di = offset of rng
UpdateRNG PROC
	push ax
	push bx
	push cx
	
	mov ax, [ds:di]
	
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
	mov [ds:di], ax
	
	pop cx
	pop bx
	pop ax

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

	mov dx, 0
	mov cx, FIRE_PIXEL_RUN_LENGTH
CopyFirePixels_Loop:
	push dx
	mov dx, SEG flameBuffer
	mov ds, dx
	mov al, [ds:bx]
	mov dx, 0A000h
	mov ds, dx
	pop dx
	
	
	; Repeat horizontally
	mov ah, FIRE_PIXEL_RUN_LENGTH
CopyFirePixels_RepeatBlockHorizontal:
	mov [ds:di], al
	inc di
	
	dec ah
	cmp ah, 0
	jne CopyFirePixels_RepeatBlockHorizontal
	
	; Next pixel in the row
	inc bx
	inc dx

	; If we're not at the end of the row, continue normally
	cmp dx, FLAME_BUFFER_WIDTH
	jne CopyFirePixels_Loop
	
	mov dx, 0
	
	; If we're done with this block of rows, go to the next loop iteration
	dec cx
	cmp cx, 0
	je CopyFirePixels_ContinueLoop
	
	; Otherwise, continue repeating the row
	sub bx, FLAME_BUFFER_WIDTH
	jmp CopyFirePixels_Loop

CopyFirePixels_ContinueLoop:
	mov cx, FIRE_PIXEL_RUN_LENGTH
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
