;=============================================================================
; TEST 02 - LCD NUMBER DISPLAY TEST
; Display temperature, pressure, and status values on LCD
; 
; Test Goal: Show formatted numbers on LCD (xx.x format)
; Expected Result: 
;   Line 1: "OTemp: 25.3 C"
;   Line 2: "CStat: 75 %"
;
; Author: [Your Name]
; Date: December 26, 2025
; IDE: MPLAB X
;=============================================================================

    PROCESSOR   16F877A
    #include    <xc.inc>
    
    ; Configuration bits for MPLAB X
    CONFIG  FOSC = HS        ; Oscillator Selection (HS oscillator)
    CONFIG  WDTE = OFF       ; Watchdog Timer (disabled)
    CONFIG  PWRTE = ON       ; Power-up Timer (enabled)
    CONFIG  BOREN = ON       ; Brown-out Reset (enabled)
    CONFIG  LVP = OFF        ; Low Voltage Programming (disabled)
    CONFIG  CPD = OFF        ; Data EEPROM Code Protection (disabled)
    CONFIG  WRT = OFF        ; Flash Program Memory Write (disabled)
    CONFIG  CP = OFF         ; Flash Program Memory Code Protection (disabled)

;-----------------------------------------------------------------------------
; PIN DEFINITIONS - LCD MODULE
;-----------------------------------------------------------------------------
LCD_RS          EQU     4       ; RD4 - Register Select
LCD_EN          EQU     5       ; RD5 - Enable signal
LCD_LINE1       EQU     0x80    ; LCD Line 1 address
LCD_LINE2       EQU     0xC0    ; LCD Line 2 address

;-----------------------------------------------------------------------------
; MEMORY ADDRESSES
;-----------------------------------------------------------------------------
DELAY_COUNT1    EQU     0x20    ; Delay counter 1
DELAY_COUNT2    EQU     0x21    ; Delay counter 2

; Test data storage
TEMP_HIGH       EQU     0x22    ; Temperature integral part
TEMP_LOW        EQU     0x23    ; Temperature fractional part
CURTAIN_STATUS  EQU     0x24    ; Curtain status (0-100%)

; Working registers for number conversion
NUM_VALUE       EQU     0x25    ; Number to convert
DIGIT_100       EQU     0x26    ; Hundreds digit
DIGIT_10        EQU     0x27    ; Tens digit
DIGIT_1         EQU     0x28    ; Ones digit

;-----------------------------------------------------------------------------
; RESET VECTOR
;-----------------------------------------------------------------------------
    PSECT   resetVec,class=CODE,delta=2
resetVec:
    PAGESEL MAIN
    GOTO    MAIN

;-----------------------------------------------------------------------------
; MAIN PROGRAM
;-----------------------------------------------------------------------------
    PSECT   code,class=CODE,delta=2

MAIN:
    ; Initialize ports
    CALL    INIT_PORTS
    
    ; Wait for LCD power-up
    CALL    DELAY_15MS
    
    ; Initialize LCD
    CALL    LCD_INIT
    
    ; Set test values
    MOVLW   25              ; Temperature = 25.3°C
    MOVWF   TEMP_HIGH
    MOVLW   3
    MOVWF   TEMP_LOW
    
    MOVLW   75              ; Curtain = 75%
    MOVWF   CURTAIN_STATUS
    
    ; Display on LCD
    CALL    DISPLAY_DATA
    
    ; Infinite loop
LOOP:
    GOTO    LOOP

;-----------------------------------------------------------------------------
; INITIALIZE PORTS
;-----------------------------------------------------------------------------
INIT_PORTS:
    ; Set PORTB as output (LCD data bus)
    BANKSEL TRISB
    CLRF    TRISB           ; PORTB all outputs
    
    ; Set PORTD bits for LCD control
    BANKSEL TRISD
    BCF     TRISD,LCD_RS    ; RD4 output (RS)
    BCF     TRISD,LCD_EN    ; RD5 output (EN)
    
    ; Clear ports
    BANKSEL PORTB
    CLRF    PORTB
    CLRF    PORTD
    
    RETURN

;-----------------------------------------------------------------------------
; LCD INITIALIZATION (8-bit mode)
;-----------------------------------------------------------------------------
LCD_INIT:
    ; Wait 15ms after power-up
    CALL    DELAY_15MS
    
    ; Function Set: 8-bit mode, 2 lines, 5x7 font
    MOVLW   0x38
    CALL    LCD_COMMAND
    CALL    DELAY_5MS
    
    ; Function Set again
    MOVLW   0x38
    CALL    LCD_COMMAND
    CALL    DELAY_200US
    
    ; Function Set third time
    MOVLW   0x38
    CALL    LCD_COMMAND
    CALL    DELAY_200US
    
    ; Display ON, Cursor OFF, Blink OFF
    MOVLW   0x0C
    CALL    LCD_COMMAND
    CALL    DELAY_200US
    
    ; Clear Display
    MOVLW   0x01
    CALL    LCD_COMMAND
    CALL    DELAY_5MS
    
    ; Entry Mode: Increment cursor, No shift
    MOVLW   0x06
    CALL    LCD_COMMAND
    CALL    DELAY_200US
    
    RETURN

;-----------------------------------------------------------------------------
; DISPLAY DATA ON LCD
;-----------------------------------------------------------------------------
DISPLAY_DATA:
    ; Line 1: "OTemp: 25.3 C"
    MOVLW   LCD_LINE1
    CALL    LCD_COMMAND
    CALL    DELAY_200US
    
    ; Display "OTemp: "
    MOVLW   'O'
    CALL    LCD_DATA
    MOVLW   'T'
    CALL    LCD_DATA
    MOVLW   'e'
    CALL    LCD_DATA
    MOVLW   'm'
    CALL    LCD_DATA
    MOVLW   'p'
    CALL    LCD_DATA
    MOVLW   ':'
    CALL    LCD_DATA
    MOVLW   ' '
    CALL    LCD_DATA
    
    ; Display temperature (25.3)
    MOVF    TEMP_HIGH,W
    CALL    DISPLAY_NUMBER     ; Display "25"
    
    MOVLW   '.'
    CALL    LCD_DATA
    
    MOVF    TEMP_LOW,W
    ADDLW   '0'                ; Convert to ASCII
    CALL    LCD_DATA
    
    MOVLW   ' '
    CALL    LCD_DATA
    MOVLW   'C'
    CALL    LCD_DATA
    
    ; Line 2: "CStat: 75 %"
    MOVLW   LCD_LINE2
    CALL    LCD_COMMAND
    CALL    DELAY_200US
    
    ; Display "CStat: "
    MOVLW   'C'
    CALL    LCD_DATA
    MOVLW   'S'
    CALL    LCD_DATA
    MOVLW   't'
    CALL    LCD_DATA
    MOVLW   'a'
    CALL    LCD_DATA
    MOVLW   't'
    CALL    LCD_DATA
    MOVLW   ':'
    CALL    LCD_DATA
    MOVLW   ' '
    CALL    LCD_DATA
    
    ; Display curtain status (75)
    MOVF    CURTAIN_STATUS,W
    CALL    DISPLAY_NUMBER
    
    MOVLW   ' '
    CALL    LCD_DATA
    MOVLW   '%'
    CALL    LCD_DATA
    
    RETURN

;-----------------------------------------------------------------------------
; DISPLAY NUMBER ON LCD
; Input: W register contains number (0-99)
; Output: Displays number in decimal on LCD
;-----------------------------------------------------------------------------
DISPLAY_NUMBER:
    MOVWF   NUM_VALUE
    
    ; Extract tens digit
    CLRF    DIGIT_10
DIV_10_LOOP:
    MOVF    NUM_VALUE,W
    SUBLW   9               ; Is it < 10?
    BTFSC   STATUS,0        ; Check carry (result >= 0)
    GOTO    DIV_10_DONE
    
    MOVLW   10
    SUBWF   NUM_VALUE,F     ; Subtract 10
    INCF    DIGIT_10,F      ; Increment tens
    GOTO    DIV_10_LOOP
    
DIV_10_DONE:
    ; Display tens digit (if not zero)
    MOVF    DIGIT_10,W
    BTFSC   STATUS,2        ; Skip if zero
    GOTO    SKIP_TENS
    ADDLW   '0'             ; Convert to ASCII
    CALL    LCD_DATA
    
SKIP_TENS:
    ; Display ones digit
    MOVF    NUM_VALUE,W
    ADDLW   '0'             ; Convert to ASCII
    CALL    LCD_DATA
    
    RETURN

;-----------------------------------------------------------------------------
; SEND COMMAND TO LCD
; Input: W register contains command
;-----------------------------------------------------------------------------
LCD_COMMAND:
    BANKSEL PORTB
    MOVWF   PORTB           ; Put command on data bus
    
    BANKSEL PORTD
    BCF     PORTD,LCD_RS    ; RS = 0 (command mode)
    BSF     PORTD,LCD_EN    ; EN = 1 (enable)
    NOP
    NOP
    BCF     PORTD,LCD_EN    ; EN = 0 (latch data)
    
    RETURN

;-----------------------------------------------------------------------------
; SEND DATA TO LCD
; Input: W register contains data
;-----------------------------------------------------------------------------
LCD_DATA:
    BANKSEL PORTB
    MOVWF   PORTB           ; Put data on data bus
    
    BANKSEL PORTD
    BSF     PORTD,LCD_RS    ; RS = 1 (data mode)
    BSF     PORTD,LCD_EN    ; EN = 1 (enable)
    NOP
    NOP
    BCF     PORTD,LCD_EN    ; EN = 0 (latch data)
    
    CALL    DELAY_200US     ; Wait for LCD to process
    RETURN

;-----------------------------------------------------------------------------
; DELAY ROUTINES
;-----------------------------------------------------------------------------
DELAY_15MS:
    MOVLW   30
    MOVWF   DELAY_COUNT1
DELAY_15MS_LOOP:
    CALL    DELAY_500US
    DECFSZ  DELAY_COUNT1,F
    GOTO    DELAY_15MS_LOOP
    RETURN

DELAY_5MS:
    MOVLW   10
    MOVWF   DELAY_COUNT1
DELAY_5MS_LOOP:
    CALL    DELAY_500US
    DECFSZ  DELAY_COUNT1,F
    GOTO    DELAY_5MS_LOOP
    RETURN

DELAY_500US:
    MOVLW   165
    MOVWF   DELAY_COUNT2
DELAY_500US_LOOP:
    NOP
    DECFSZ  DELAY_COUNT2,F
    GOTO    DELAY_500US_LOOP
    RETURN

DELAY_200US:
    MOVLW   66
    MOVWF   DELAY_COUNT2
DELAY_200US_LOOP:
    NOP
    DECFSZ  DELAY_COUNT2,F
    GOTO    DELAY_200US_LOOP
    RETURN

;-----------------------------------------------------------------------------
; End of program
;-----------------------------------------------------------------------------
