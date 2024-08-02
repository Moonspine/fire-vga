; DOS Misc. Function library
; Copyright (c) 2022 Moonspine
; Available for use under the MIT license

; Exits to DOS
exitToDOS PROC
	mov ah, 4ch
	int 21h
	ret
exitToDOS ENDP
