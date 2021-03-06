.include "m8515def.inc"

;#####
;# PORTA = LED + LCD
;# PORTB = LCD DATA
;# PINC = Button
;# PORT/PIN E = keypad
;#####

.def temp = r16
.def lcd_data = r17
.def wait_fall = r18
.def count_1 = r19
.def count_2 = r20
.def choose = r21
.def enable = r22
.def keypad_data = r23
.def keypad_state = r24
.def can_enable_again = r25
.def mod = r6
.def div = r7
.def check_data = r8

.equ count_1_ram = 0x01
.equ count_2_ram = 0x02

.org $00
rjmp INIT_STACK
.org $01
rjmp ENABLE_STATE
.org $06
rjmp TIMER

INIT_STACK:
	ldi temp, LOW(RAMEND)
	out SPL, temp
	ldi temp, HIGH(RAMEND)
	out SPH, temp

PRE_PROGRAM:
	rcall INIT
	rcall UPDATE_COUNT_LCD
	ldi temp,0b00001010 	
	out MCUCR,temp		; falling edge activated
	ldi temp,0b11100000	; enabled for INT_0+1+2	 
	out GICR,temp
	ldi temp, (1<<CS10)	;
	out TCCR1B, temp			
	ldi temp,1<<TOV1
	out TIFR,temp		; Interrupt if overflow occurs in T/C0
	ldi temp,1<<TOIE1
	out TIMSK,temp		; Enable Timer/Counter0 Overflow int
	sei
	
PROGRAM:
	cpi can_enable_again, 1
	breq RESET_TIMER
	AFTER_RESET:
	in temp, PINC
	cpi temp, 1
	breq CHOOSE_1
	cpi temp, 2
	breq CHOOSE_2
	EXIT_IF_ADD:
	rjmp PROGRAM

RESET_TIMER:
	clr temp
	out TCNT1L, temp
	out TCNT1H, temp
	rjmp AFTER_RESET

INIT:
	ldi temp, 0xFF
	out DDRA, temp ; led
	out DDRB, temp ; lcd
	ldi temp, 0x00
	out DDRC, temp ; button
	ldi temp, 0x00
	out DDRE, temp ; keypad
	ldi temp, 0x00
	out PORTA, temp ; set all led off
	ldi temp, 0
	sts count_1_ram, temp
	sts count_2_ram, temp
	ret

TO_PROGRAM:
	rcall UPDATE_COUNT_LCD
	rjmp PROGRAM

TO_EXIT_IF_ADD:
	rjmp EXIT_IF_ADD


CHOOSE_1:
	cpi enable, 1
	brne EXIT_IF_ADD
	ldi choose, 1
	rcall CLEAR_LCD
	rcall WRITE_CONFIRMATION_LCD
	rcall CONFIRMATION
	rjmp EXIT_IF_ADD

CHOOSE_2:
	cpi enable, 1
	brne TO_EXIT_IF_ADD
	ldi choose, 2
	rcall CLEAR_LCD
	rcall WRITE_CONFIRMATION_LCD
	rcall CONFIRMATION
	rjmp EXIT_IF_ADD

;#######
;# LCD
;#######
	
CLEAR_LCD:
	cbi PORTA, 5
	cbi PORTA, 6
	ldi temp, 0x01
	out PORTB, temp
	sbi PORTA, 7
	cbi PORTA, 7
	ret

WRITE_LCD:
	sbi PORTA, 5
	cbi PORTA, 6
	out PORTB, lcd_data
	sbi PORTA, 7
	cbi PORTA, 7
	ret

TO_LINE_2_LCD:
	cbi PORTA, 5
	cbi PORTA, 6
	ldi temp, 0b11000000
	out PORTB, temp
	sbi PORTA, 7
	cbi PORTA, 7
	ret

WRITE_CONFIRMATION_LCD:
	ldi	ZH,high(2*confirmation_message)	; Load high part of byte address into ZH
	ldi	ZL,low(2*confirmation_message)	; Load low part of byte address into ZL

WRITE_CONFIRMATION_LCD_PRINT:
	lpm			; Load byte from program memory into r0

	tst	r0		; Check if we've reached the end of the message
	breq WRITE_CONF_LCD_BOT		; If so, quit

	mov lcd_data, r0		; Put the character onto Port B
	rcall WRITE_LCD
	adiw ZL,1		; Increase Z registers
	rjmp WRITE_CONFIRMATION_LCD_PRINT

; this should print name of the candidate
WRITE_CONF_LCD_BOT:
	rcall TO_LINE_2_LCD
	ldi lcd_data, 0x30
	add lcd_data, choose
	rcall WRITE_LCD
	ret
	
;#######
;# CHOOSE
;#######

CONFIRMATION:
	in temp, PINC
	cpi temp, 8
	breq TO_PROGRAM
	cpi temp, 4
	brne CONFIRMATION
	cpi choose, 1
	breq ADD_1
	cpi choose, 2
	breq ADD_2
	EXIT_IF_CONFIRMATION:
	ldi enable, 0
	ldi temp, 0
	out PORTA, temp
	ret

ADD_1:
	lds count_1, count_1_ram
	ldi temp, 1
	add count_1, temp
	sts count_1_ram, count_1
	ldi can_enable_again, 0
	rcall UPDATE_COUNT_LCD
	rjmp EXIT_IF_CONFIRMATION

ADD_2:
	lds count_2, count_2_ram
	ldi temp, 1
	add count_2, temp
	sts count_2_ram, count_2
	ldi can_enable_again, 0
	rcall UPDATE_COUNT_LCD
	rjmp EXIT_IF_CONFIRMATION

UPDATE_COUNT_LCD:
	rcall CLEAR_LCD
	mov check_data, count_1
	rcall WRITE_LCD_COUNT
	rcall TO_LINE_2_LCD
	mov check_data, count_2
	rcall WRITE_LCD_COUNT
	ret

WRITE_LCD_COUNT:
	mov mod, check_data
	ldi temp, 0
	mov div, temp
	rcall CHECK100
	ldi temp, 0
	mov div, temp
	mov check_data, mod
	rcall CHECK10
	ldi temp, 0
	mov div, temp
	mov check_data, mod
	rcall CHECK1
	ret

CHECK100:
	ldi temp, 100
	sub check_data, temp
	tst check_data
	brmi PRINT_DATA
	ldi temp, 1
	add div, temp
	mov mod, check_data
	rjmp CHECK100

CHECK10:
	ldi temp, 10
	sub check_data, temp
	tst check_data
	brmi PRINT_DATA
	ldi temp, 1
	add div, temp
	mov mod, check_data
	rjmp CHECK10

CHECK1:
	ldi temp, 1
	sub check_data, temp
	tst check_data
	brmi PRINT_DATA
	ldi temp, 1
	add div, temp
	mov mod, check_data
	rjmp CHECK1

PRINT_DATA:
	ldi lcd_data, 0x30
	add lcd_data, div
	rcall WRITE_LCD
	ret

ENABLE_STATE:
	cpi can_enable_again, 0
	breq RET_INT
	ldi enable, 1
	ldi temp, 0x01
	OUT PORTA, temp

RET_INT:
	reti

TIMER:
	ldi can_enable_again, 1
	reti

confirmation_message:
.db "Choose", 0, 0
