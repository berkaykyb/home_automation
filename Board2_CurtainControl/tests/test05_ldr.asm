;=============================================================================
; TEST 05 - LDR SENSOR TEST
; Test LDR (Light Dependent Resistor) sensor reading
; Pin: RA1/AN1 (analog input)
; Display: Raw ADC value and light status (Dark/Normal/Bright)
;=============================================================================

    PROCESSOR   16F877A
    #include    <xc.inc>
    
    CONFIG  FOSC = HS
    CONFIG  WDTE = OFF
    CONFIG  PWRTE = ON
    CONFIG  BOREN = ON
    CONFIG  LVP = OFF
    CONFIG  CPD = OFF
    CONFIG  WRT = OFF
    CONFIG  CP = OFF

;-----------------------------------------------------------------------------
; CONSTANTS
;-----------------------------------------------------------------------------
LCD_RS          EQU     4
LCD_EN          EQU     5
LCD_LINE1       EQU     0x80
LCD_LINE2       EQU     0xC0

;-----------------------------------------------------------------------------
; VARIABLES
;-----------------------------------------------------------------------------
DELAY_COUNT1    EQU     0x20
DELAY_COUNT2    EQU     0x21
DELAY_COUNT3    EQU     0x22
LDR_VALUE       EQU     0x23        ; LDR ADC value (0-255)
TEMP_VAL        EQU     0x24
DIGIT_100       EQU     0x25
DIGIT_10        EQU     0x26
DIGIT_1         EQU     0x27

;-----------------------------------------------------------------------------
    PSECT   resetVec,class=CODE,delta=2
resetVec:
    GOTO    START

;-----------------------------------------------------------------------------
    PSECT   code,class=CODE,delta=2

START:
    ; Configure ports
    BANKSEL TRISB
    CLRF    TRISB           ; PORTB output (LCD data)
    
    BANKSEL TRISD  
    BCF     TRISD,4         ; RD4 output (LCD RS)
    BCF     TRISD,5         ; RD5 output (LCD EN)
    
    BANKSEL TRISA
    BSF     TRISA,1         ; RA1 input (LDR)
    
    ; Configure ADC
    BANKSEL ADCON1
    MOVLW   0x04            ; Left justified, AN0-AN4 analog
    MOVWF   ADCON1
    
    BANKSEL ADCON0
    MOVLW   0x89            ; Fosc/32, Channel 1 (AN1), ADC ON
    MOVWF   ADCON0
    
    ; Channel change delay - CRITICAL!
    CALL    DELAY_20MS      ; Wait for channel multiplexer to settle
    
    ; Clear ports
    BANKSEL PORTB
    CLRF    PORTB
    CLRF    PORTD
    
    ; Initialize LCD
    CALL    DELAY_20MS
    CALL    LCD_INIT
    
    ; Show labels
    CALL    SHOW_LABELS

;-----------------------------------------------------------------------------
; MAIN LOOP
;-----------------------------------------------------------------------------
MAIN_LOOP:
    ; Read LDR
    CALL    READ_LDR
    
    ; Update display
    CALL    UPDATE_DISPLAY
    
    ; Delay
    CALL    DELAY_20MS
    CALL    DELAY_20MS
    CALL    DELAY_20MS
    CALL    DELAY_20MS
    CALL    DELAY_20MS
    
    GOTO    MAIN_LOOP

;-----------------------------------------------------------------------------
; READ_LDR - Read LDR sensor value
;-----------------------------------------------------------------------------
READ_LDR:
    BANKSEL ADCON0
    BSF     ADCON0,2        ; Start conversion
    
    ; ADC Acquisition delay
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    
WAIT_LDR:
    BTFSC   ADCON0,2
    GOTO    WAIT_LDR
    
    BANKSEL ADRESH
    MOVF    ADRESH,W        ; Read high 8 bits (left justified)
    BANKSEL PORTB
    MOVWF   LDR_VALUE
    
    RETURN

;-----------------------------------------------------------------------------
; SHOW_LABELS
;-----------------------------------------------------------------------------
SHOW_LABELS:
    ; Line 1: "LDR ADC:"
    MOVLW   LCD_LINE1
    CALL    LCD_CMD
    
    MOVLW   'L'
    CALL    LCD_CHR
    MOVLW   'D'
    CALL    LCD_CHR
    MOVLW   'R'
    CALL    LCD_CHR
    MOVLW   ' '
    CALL    LCD_CHR
    MOVLW   'A'
    CALL    LCD_CHR
    MOVLW   'D'
    CALL    LCD_CHR
    MOVLW   'C'
    CALL    LCD_CHR
    MOVLW   ':'
    CALL    LCD_CHR
    
    ; Line 2: "Status:"
    MOVLW   LCD_LINE2
    CALL    LCD_CMD
    
    MOVLW   'S'
    CALL    LCD_CHR
    MOVLW   't'
    CALL    LCD_CHR
    MOVLW   'a'
    CALL    LCD_CHR
    MOVLW   't'
    CALL    LCD_CHR
    MOVLW   'u'
    CALL    LCD_CHR
    MOVLW   's'
    CALL    LCD_CHR
    MOVLW   ':'
    CALL    LCD_CHR
    
    RETURN

;-----------------------------------------------------------------------------
; UPDATE_DISPLAY
;-----------------------------------------------------------------------------
UPDATE_DISPLAY:
    ; Update Line 1 - Show ADC value
    MOVLW   LCD_LINE1 + 9
    CALL    LCD_CMD
    
    MOVF    LDR_VALUE,W
    CALL    DISPLAY_NUMBER
    
    MOVLW   ' '
    CALL    LCD_CHR
    MOVLW   ' '
    CALL    LCD_CHR
    
    ; Update Line 2 - Show light status
    MOVLW   LCD_LINE2 + 8
    CALL    LCD_CMD
    
    ; Determine status based on LDR value (REVERSED LOGIC)
    ; Bright: < 85 (slider high = low resistance = bright)
    ; Normal: 85-170
    ; Dark: > 170 (slider low = high resistance = dark)
    
    MOVF    LDR_VALUE,W
    SUBLW   85
    BTFSC   STATUS,0
    GOTO    SHOW_BRIGHT     ; LDR_VALUE < 85 = Bright
    
    MOVF    LDR_VALUE,W
    SUBLW   170
    BTFSC   STATUS,0
    GOTO    SHOW_NORMAL     ; LDR_VALUE < 170 = Normal
    
    ; Dark (LDR_VALUE >= 170)
    MOVLW   'D'
    CALL    LCD_CHR
    MOVLW   'a'
    CALL    LCD_CHR
    MOVLW   'r'
    CALL    LCD_CHR
    MOVLW   'k'
    CALL    LCD_CHR
    MOVLW   ' '
    CALL    LCD_CHR
    MOVLW   ' '
    CALL    LCD_CHR
    MOVLW   ' '
    CALL    LCD_CHR
    MOVLW   ' '
    CALL    LCD_CHR
    RETURN
    
SHOW_BRIGHT:
    MOVLW   'B'
    CALL    LCD_CHR
    MOVLW   'r'
    CALL    LCD_CHR
    MOVLW   'i'
    CALL    LCD_CHR
    MOVLW   'g'
    CALL    LCD_CHR
    MOVLW   'h'
    CALL    LCD_CHR
    MOVLW   't'
    CALL    LCD_CHR
    MOVLW   ' '
    CALL    LCD_CHR
    MOVLW   ' '
    CALL    LCD_CHR
    RETURN
    
SHOW_NORMAL:
    MOVLW   'N'
    CALL    LCD_CHR
    MOVLW   'o'
    CALL    LCD_CHR
    MOVLW   'r'
    CALL    LCD_CHR
    MOVLW   'm'
    CALL    LCD_CHR
    MOVLW   'a'
    CALL    LCD_CHR
    MOVLW   'l'
    CALL    LCD_CHR
    MOVLW   ' '
    CALL    LCD_CHR
    MOVLW   ' '
    CALL    LCD_CHR
    RETURN

;-----------------------------------------------------------------------------
; DISPLAY_NUMBER - Convert number to 3 digits and display
; Input: W = number (0-255)
;-----------------------------------------------------------------------------
DISPLAY_NUMBER:
    MOVWF   TEMP_VAL
    CLRF    DIGIT_100
    CLRF    DIGIT_10
    CLRF    DIGIT_1
    
    ; Hundreds digit
LOOP_100:
    MOVLW   100
    SUBWF   TEMP_VAL,W
    BTFSS   STATUS,0
    GOTO    DONE_100
    MOVWF   TEMP_VAL
    INCF    DIGIT_100,F
    GOTO    LOOP_100
DONE_100:

    ; Tens digit  
LOOP_10:
    MOVLW   10
    SUBWF   TEMP_VAL,W
    BTFSS   STATUS,0
    GOTO    DONE_10
    MOVWF   TEMP_VAL
    INCF    DIGIT_10,F
    GOTO    LOOP_10
DONE_10:

    ; Ones digit
    MOVF    TEMP_VAL,W
    MOVWF   DIGIT_1
    
    ; Display all 3 digits
    MOVF    DIGIT_100,W
    ADDLW   '0'
    CALL    LCD_CHR
    
    MOVF    DIGIT_10,W
    ADDLW   '0'
    CALL    LCD_CHR
    
    MOVF    DIGIT_1,W
    ADDLW   '0'
    CALL    LCD_CHR
    
    RETURN

;-----------------------------------------------------------------------------
; LCD FUNCTIONS
;-----------------------------------------------------------------------------
LCD_INIT:
    CALL    DELAY_20MS
    
    MOVLW   0x38            ; 8-bit, 2 lines, 5x8 font
    CALL    LCD_CMD
    
    MOVLW   0x0C            ; Display ON, cursor OFF
    CALL    LCD_CMD
    
    MOVLW   0x06            ; Entry mode: increment, no shift
    CALL    LCD_CMD
    
    MOVLW   0x01            ; Clear display
    CALL    LCD_CMD
    CALL    DELAY_20MS
    
    RETURN

LCD_CMD:
    MOVWF   PORTB
    BCF     PORTD,LCD_RS
    CALL    LCD_PULSE
    RETURN

LCD_CHR:
    MOVWF   PORTB
    BSF     PORTD,LCD_RS
    CALL    LCD_PULSE
    RETURN

LCD_PULSE:
    BSF     PORTD,LCD_EN
    CALL    DELAY_500US
    BCF     PORTD,LCD_EN
    CALL    DELAY_500US
    RETURN

;-----------------------------------------------------------------------------
; DELAY FUNCTIONS
;-----------------------------------------------------------------------------
DELAY_20MS:
    MOVLW   40
    MOVWF   DELAY_COUNT3
DELAY_20MS_LOOP:
    CALL    DELAY_500US
    DECFSZ  DELAY_COUNT3,F
    GOTO    DELAY_20MS_LOOP
    RETURN

DELAY_500US:
    MOVLW   250
    MOVWF   DELAY_COUNT2
DELAY_500US_LOOP:
    NOP
    DECFSZ  DELAY_COUNT2,F
    GOTO    DELAY_500US_LOOP
    RETURN
