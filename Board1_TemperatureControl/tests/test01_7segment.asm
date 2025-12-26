;=============================================================================
; TEST 01: 7-SEGMENT DISPLAY (4 Digit Multiplexed)
; Board: Board1 Temperature Control
; Display: 25.9 (Test Pattern)
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
; PIN CONFIGURATION
;-----------------------------------------------------------------------------
; 7-Segment (Common Cathode, Active HIGH):
;   Segments: PORTD (RD0=a, RD1=b, RD2=c, RD3=d, RD4=e, RD5=f, RD6=g, RD7=dp)
;   Digits:   PORTA (RA2=D1, RA3=D2, RA4=D3, RA5=D4)
;
; Display Format: D1 D2 D3 D4
;                 2  5  .  9

;-----------------------------------------------------------------------------
; VARIABLES
;-----------------------------------------------------------------------------
DELAY_COUNT1    EQU     0x20
DELAY_COUNT2    EQU     0x21
DIGIT_INDEX     EQU     0x22

; Display digits (what to show on each position)
DIGIT_1         EQU     0x23    ; Leftmost: 2
DIGIT_2         EQU     0x24    ; Second: 5
DIGIT_3         EQU     0x25    ; Third: 9 (with decimal point)
DIGIT_4         EQU     0x26    ; Rightmost: blank or additional digit

;-----------------------------------------------------------------------------
; 7-SEGMENT PATTERNS (Common Cathode)
; Bit order: dp g f e d c b a
; Patterns stored in lookup table function
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
    PSECT   resetVec,class=CODE,delta=2
resetVec:
    GOTO    START

;-----------------------------------------------------------------------------
    PSECT   code,class=CODE,delta=2

START:
    ; Configure PORTA as digital (disable ADC on RA pins)
    BANKSEL ADCON1
    MOVLW   0x06            ; All digital (no analog)
    MOVWF   ADCON1
    
    ; Configure ports
    BANKSEL TRISD
    CLRF    TRISD           ; PORTD output (segments)
    
    BANKSEL TRISA
    BCF     TRISA,2         ; RA2 output (D1)
    BCF     TRISA,3         ; RA3 output (D2)
    BCF     TRISA,4         ; RA4 output (D3)
    BCF     TRISA,5         ; RA5 output (D4)
    
    ; Clear ports
    BANKSEL PORTD
    CLRF    PORTD
    BANKSEL PORTA
    CLRF    PORTA
    
    ; Initialize display values (25.9)
    MOVLW   2
    MOVWF   DIGIT_1         ; D1 = 2
    MOVLW   5
    MOVWF   DIGIT_2         ; D2 = 5
    MOVLW   9
    MOVWF   DIGIT_3         ; D3 = 9 (with decimal point)
    MOVLW   10
    MOVWF   DIGIT_4         ; D4 = blank
    
    CLRF    DIGIT_INDEX

;-----------------------------------------------------------------------------
; MAIN LOOP - Multiplexed Display (25.9)
;-----------------------------------------------------------------------------
MAIN_LOOP:
    BANKSEL PORTD
    
    ; Digit 1: "2"
    MOVF    DIGIT_1,W
    CALL    GET_SEGMENT_PATTERN
    MOVWF   PORTD
    MOVLW   0x04
    MOVWF   PORTA
    CALL    DELAY_2MS
    
    ; Digit 2: "5" with DP (decimal point after 5 = 25.9)
    MOVF    DIGIT_2,W
    CALL    GET_SEGMENT_PATTERN
    IORLW   0x80            ; Add decimal point
    MOVWF   PORTD
    MOVLW   0x08
    MOVWF   PORTA
    CALL    DELAY_2MS
    
    ; Digit 3: "9"
    MOVF    DIGIT_3,W
    CALL    GET_SEGMENT_PATTERN
    MOVWF   PORTD
    MOVLW   0x10
    MOVWF   PORTA
    CALL    DELAY_2MS
    
    ; Digit 4: blank
    MOVLW   10
    CALL    GET_SEGMENT_PATTERN
    MOVWF   PORTD
    MOVLW   0x20
    MOVWF   PORTA
    CALL    DELAY_2MS
    
    GOTO    MAIN_LOOP

;-----------------------------------------------------------------------------
; GET_SEGMENT_PATTERN - Convert digit (0-10) to 7-segment pattern
; Input: W = digit (0-9, 10=blank)
; Output: W = segment pattern
;-----------------------------------------------------------------------------
GET_SEGMENT_PATTERN:
    MOVWF   DIGIT_INDEX
    
    MOVLW   0
    SUBWF   DIGIT_INDEX,W
    BTFSC   STATUS,2
    RETLW   0x3F            ; 0
    
    MOVLW   1
    SUBWF   DIGIT_INDEX,W
    BTFSC   STATUS,2
    RETLW   0x06            ; 1
    
    MOVLW   2
    SUBWF   DIGIT_INDEX,W
    BTFSC   STATUS,2
    RETLW   0x5B            ; 2
    
    MOVLW   3
    SUBWF   DIGIT_INDEX,W
    BTFSC   STATUS,2
    RETLW   0x4F            ; 3
    
    MOVLW   4
    SUBWF   DIGIT_INDEX,W
    BTFSC   STATUS,2
    RETLW   0x66            ; 4
    
    MOVLW   5
    SUBWF   DIGIT_INDEX,W
    BTFSC   STATUS,2
    RETLW   0x6D            ; 5
    
    MOVLW   6
    SUBWF   DIGIT_INDEX,W
    BTFSC   STATUS,2
    RETLW   0x7D            ; 6
    
    MOVLW   7
    SUBWF   DIGIT_INDEX,W
    BTFSC   STATUS,2
    RETLW   0x07            ; 7
    
    MOVLW   8
    SUBWF   DIGIT_INDEX,W
    BTFSC   STATUS,2
    RETLW   0x7F            ; 8
    
    MOVLW   9
    SUBWF   DIGIT_INDEX,W
    BTFSC   STATUS,2
    RETLW   0x6F            ; 9
    
    RETLW   0x00            ; Blank (10 or other)

;-----------------------------------------------------------------------------
; DELAY_2MS - Delay for multiplexing (approximately 2ms)
;-----------------------------------------------------------------------------
DELAY_2MS:
    MOVLW   4
    MOVWF   DELAY_COUNT1
DL2_OUTER:
    MOVLW   250
    MOVWF   DELAY_COUNT2
DL2_INNER:
    NOP
    DECFSZ  DELAY_COUNT2,F
    GOTO    DL2_INNER
    DECFSZ  DELAY_COUNT1,F
    GOTO    DL2_OUTER
    RETURN

    END
