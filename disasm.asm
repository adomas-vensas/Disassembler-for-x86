; Purpose: read command line argument (file name without extension)
; Open the file and rewrite its contents according to the plan of disassembler

;<<<<<<<<<<< 1. MACROS >>>>>>>>>>>>>;
%macro writeln 1										;outputs a string to stdout
          push ax
          push dx
          mov ah, 09
          mov dx, %1
          int 21h
          pop dx
          pop ax
		  
%endmacro
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
%macro crlf 0												;outputs CR and NL to stdout
		push ax
		push dx
		mov ah, 09
		mov dx, naujaEilute
		int 21h
		pop dx
		pop ax
		
%endmacro
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
%macro readNext 1									;Reads specified amount of bytes from file
		push cx
		
		mov cx, 0
		mov cl, %1
		mov ah, 0x3F
		int 0x21
		jc %%setEnd
		cmp ax, 0x00
        jne %%continue
		
		%%setEnd
		stc
		jmp %%finish
		
		%%continue:
		add [lseek], ax
		mov ax, [si]
		
		pop cx
		
		%%finish
%endmacro
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
org 100h   

section .text
;<<<<<<<<<<< 2. MAIN >>>>>>>>>>>>>;
main:
   ; At start DS and ES point to PSP
   ; PSP + 0x80 => command line argument length (without extension)

   call readComArgument								;get file name and add '.com' to it
   jnc .openFile												
   writeln errorReadingArgument
   jmp .cont
   
   .openFile:
   mov dx, comLineArgument      
   call openFile												;open input file
   jnc .readFile
   writeln errorOpeningFile
   jmp .cont

   .readFile:														;read from file
   mov bx, [currentFile]          
   mov dx, takenArgument          
   call readFile
   jnc .end
   writeln errorReadingFile

   .end:
   mov bx, [currentFile]          
   call closeFile												;close file
   .cont:
   mov ah, 0x4C											;end program
   int 0x21
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
openFile:  
	; DX - file's name address
	; CF set if error
	push ax
	push dx

	mov ah, 0x3D
	mov al, 0x00
	int 0x21

	jc .end
	mov [currentFile], ax

	.end:  
	pop dx
	pop ax
ret   

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
closeFile:  
	; DX - file's name address
	; CF set if error 
	push ax
	push bx

	mov ah, 0x3E
	int 0x21

	.end:  
	pop dx
	pop ax
ret
		
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
readComArgument:
	 ; Read and prepare the argument
	 ; If no argument - set CF, else CF = 0;

	 push bx
	 push di
	 push si 
	 push ax

	 xor bx, bx
	 xor si, si
	 xor di, di

	 mov bl, [0x80]
	 mov [comLineLength], bl
	 mov si, 0x0081  
	 mov di, comLineArgument
	 push cx
	 mov cx, bx
	 mov ah, 0x00
	 cmp cx, 0x0000
	 jne .all
	 stc 
	 jmp .end

	 .all:
	 mov al, [si]
	 cmp al, ' '
	 je .cont
	 cmp al, 0x0D
	 je .cont
	 cmp al, 0x0A
	 je .cont
	 mov [di], al
	 mov ah, 0x01                  ; ah - flag, that there was atleast one 'non-space'
	 inc di     
	 jmp .followUp
	 .cont:
	 cmp ah, 0x01                  ; check if there have already been 'non-spaces'  
	 je .leave 
	 .followUp:
	 inc si
 
	 loop .all
	 .leave: 
	 cmp ah, 0x01                  ; check if there have already been 'non-spaces'  
	 je .addCOM
	 stc                         ; error 
	 jmp .end
	 .addCOM:
	 mov [di], byte '.'
	 mov [di + 1], byte 'C'
	 mov [di + 2], byte 'O'
	 mov [di + 3], byte 'M'
	 clc                         ; no error
	 .end
	 pop cx
	 pop ax
	 pop si
	 pop di 
	 pop dx
ret
		 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;<<<<<<<<<<< 3. READ FILE >>>>>>>>>>>>>;
readFile:  
	; Form the instruction
	; BX - files's descriptor
	; DX - buffer

	 push ax
	 push bx
	 push cx
	 push dx
	 push si
	 push bp
	 mov bp, sp
	 sub sp, 20
	 %define MD byte [bp - 2]							;MOD
	 %define REG byte [bp - 4]							;REG
	 %define RM byte [bp - 6]							;R/M
	 %define BYTE_NUM byte [bp - 8]			;Amount of bytes to read
	 %define D_W byte [bp - 10]						;Direction and Word byte
	 %define S_W byte [bp - 12]						;Store word
	 %define V_W byte [bp - 14]						;Variable word
	 %define BYTE_READ byte [bp - 16]		;Amount of bytes to read
	 %define W byte [bp - 18]							;Word bit
	 %define PREFIX byte [bp - 20]					;Prefix byte
	 mov BYTE_NUM, 0x00
	 mov MD, 0x00
	 mov REG, 0x00
	 mov RM, 0x00
	 mov BYTE_READ, 0x00
	 mov PREFIX, 0xFF
	 mov W, 0xFF
	 mov D_W, 0xFF
	 mov S_W, 0xFF
	 mov V_W, 0xFF
	 
	 ; Reading the instruction byte and looping until no more to read
	 mov si, dx
	 .goAgain:
	 readNext 1
	 jc .goToEnd								; if CF set - stop reading
		 
		 ;--------------------START OF PREFIXES-----------------------------------------------------
		 
		 cmp al, 0x26							;prefix ES
		 jne .maybePrefixCS
		 mov PREFIX, 0x00
		 readNext 1
		 jmp .maybeJMPdirect
		 
		 .maybePrefixCS
		 cmp al, 0x2E							;prefix CS
		 jne .maybePrefixSS
		 mov PREFIX, 0x01
		 readNext 1
		 jmp .maybeJMPdirect
		 
		 .maybePrefixSS
		 cmp al, 0x36							;prefix SS
		 jne .maybePrefixDS
		 mov PREFIX, 0x02
		 readNext 1
		 jmp .maybeJMPdirect
		 
		 .maybePrefixDS
		 cmp al, 0x3C							;prefix DS
		 jne .maybeCLC
		 mov PREFIX, 0x03
		 readNext 1
		 jmp .maybeJMPdirect
		 
		 ;--------------------END OF PREFIXES-----------------------------------------------------
		 ;--------------------START OF ONE BYTE INSTRUCTIONS------------------------
		 
		.maybeCLC
         cmp al, 0xF8                            ; CLC
         jne .maybeCMC
         writeln strCLC
		 crlf
         jmp .end
                 
         .maybeCMC:
         cmp al, 0xF5                            ; CMC
         jne .maybeSTC
         writeln strCMC
		 crlf
         jmp .end

         .maybeSTC:
         cmp al, 0xF9                            ; STC
         jne .maybeRET
         writeln strSTC
		 crlf
         jmp .end
         
         .maybeRET:
         cmp al, 0xC3                            ; RET
         jne .maybeRETF
         writeln strRET
		 crlf
         jmp .end
         
                  
         .maybeRETF:
         cmp al, 0xCB                            ; RETF
         jne .maybeCLI
         writeln strRETF
		 crlf
         jmp .end
		 
		 .maybeCLI
         cmp al, 0xFA                            ; CLI
         jne .maybeCLD
         writeln strCLI
		 crlf
         jmp .end
		 
		 .maybeCLD
         cmp al, 0xFC                            ; CLD
         jne .maybeSTD
         writeln strCLD
		 crlf
         jmp .end
		 
		 .maybeSTD
         cmp al, 0xFD                            ; STD
         jne .maybeSTI
         writeln strSTD
		 crlf
         jmp .end
		 
		 .maybeSTI
         cmp al, 0xFB                            ; STI
         jne .maybeHLT
         writeln strSTI
		 crlf
         jmp .end
		 
		 .maybeHLT
         cmp al, 0xF4                            ; HLT
         jne .maybeWAIT
         writeln strHLT
		 crlf
         jmp .end
		 
		 .maybeWAIT
         cmp al, 0x9B                            ; WAIT
         jne .maybeLOCK
         writeln strWAIT
		 crlf
         jmp .end
		 
		 .maybeLOCK
         cmp al, 0xF0                            ; LOCK
         jne .maybeINTO
         writeln strLOCK
		 crlf
         jmp .end
		 
		 .maybeINTO
         cmp al, 0xCE                           ; INTO
         jne .maybeIRET
         writeln strINTO
		 crlf
         jmp .end
		 
		 .maybeIRET
         cmp al, 0xCF                           ; IRET
         jne .maybeINT_3h
         writeln strIRET
		 crlf
         jmp .end
		 
		 .maybeINT_3h
         cmp al, 0xCC                           ; INT 3h
         jne .maybeINT_4h
         writeln strINT_3h
		 crlf
         jmp .end
		 
		 .maybeINT_4h
         cmp al, 0xCE                           ; INT 4h
         jne .maybeCBW
         writeln strINT_4h
		 crlf
         jmp .end
		 
		 .maybeCBW
         cmp al, 0x98                           ; CBW
         jne .maybeCWD
         writeln strICBW
		 crlf
         jmp .end
		 
		 .maybeCWD
         cmp al, 0x99                           ; CWD
         jne .maybeAAS
         writeln strICWD
		 crlf
         jmp .end
		 
		 .maybeAAS
         cmp al, 0x3F                           ; AAS
         jne .maybeDAS
         writeln strIAAS
		 crlf
         jmp .end
		 
		 .maybeDAS
         cmp al, 0x2F                           ; DAS
         jne .maybeDAA
         writeln strIDAS
		 crlf
         jmp .end
		 
		 .maybeDAA
		 cmp al, 0x27							; DAA
		 jne .maybeXLAT
		 writeln strDAA
		 crlf
		 jmp .end
		 
		 .maybeXLAT							;XLAT
		 cmp al, 0xD7
		 jne .maybeAAM
		 writeln strXLAT
		 crlf
		 jmp .end
		 
		 .maybeAAM								; AAM
		 cmp al, 0xD4							
		 jne .maybeAAD
		 writeln strAAM
		 readNext 1
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .maybeAAD								; AAD	
		 cmp al, 0xD5
		 jne .maybeAAA
		 writeln strAAD
		 readNext 1
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .maybeAAA
         cmp al, 0x37                           ; AAA
         jne .maybeLAHF
         writeln strAAA
		 crlf
         jmp .end
		 
		 .maybeLAHF
         cmp al, 0x9F                           ; LAHF
         jne .maybeSAHF
         writeln strILAHF
		 crlf
         jmp .end
		 
		 .maybeSAHF
         cmp al, 0x9E                           ; SAHF
         jne .maybePUSHF
         writeln strISAHF
		 crlf
         jmp .end
		 
		 .maybePUSHF
         cmp al, 0x9C                           ; PUSHF
         jne .maybePOPF
         writeln strIPUSHF
		 crlf
         jmp .end
		 
		 .maybePOPF
         cmp al, 0x9D                           ; POPF
         jne .maybeLOOPNE
         writeln strIPOPF
		 crlf
         jmp .end
		 
		 .maybeLOOPNE
		 cmp al, 0xE0							;LOOPNE
		 jne .maybeLOOPE
		 writeln strLOOPNE
		 jmp .getDisplacementByte
		 
		 .maybeLOOPE
		 cmp al, 0xE1							;LOOPE
		 jne .maybeLOOP
		 writeln strLOOPE
		 jmp .getDisplacementByte
		 
		 .maybeLOOP
		 cmp al, 0xE2							;LOOP
		 jne .maybeJCXZ
		 writeln strLOOP
		 jmp .getDisplacementByte
		 
		 .maybeJCXZ
		 cmp al, 0xE3							;JCXZ
		 jne .maybeREPNE
		 writeln strJCXZ
		 jmp .getDisplacementByte
		 
		 .maybeREPNE							;REPNE
		 cmp al, 0xF2
		 jne .maybeREPE
		 writeln strREPNE
		 crlf
		 jmp .end
		 
		 .maybeREPE							;REPE
		 cmp al, 0xF3
		 jne .maybeMOVSB
		 writeln strREPE
		 crlf
		 jmp .end
		
		 .maybeMOVSB						;MOSVB
		 cmp al, 0xA4
		 jne .maybeMOVSW
		 writeln strMOVSB
		 crlf
		 jmp .end
		 
		 .maybeMOVSW						;MOVSW
		 cmp al, 0xA5
		 jne .maybeCMPSB
		 writeln strMOVSW
		 crlf
		 jmp .end
		 
		 .maybeCMPSB						;CMPSB
		 cmp al, 0xA6
		 jne .maybeCMPSW
		 writeln strCMPSB
		 crlf
		 jmp .end
		 
		 .maybeCMPSW						;CMPSW
		 cmp al, 0xA7
		 jne .maybeSCASB
		 writeln strCMPSW
		 crlf
		 jmp .end
		 
		 .maybeSCASB							;SCASB
		 cmp al, 0xAE
		 jne .maybeSCASW
		 writeln strSCASB
		 crlf
		 jmp .end
		 
		 .maybeSCASW						;SCASW
		 cmp al, 0xAF
		 jne .maybeLODSB
		 writeln strSCASW
		 crlf
		 jmp .end
		 
		 .maybeLODSB							;LODSB
		 cmp al, 0xAC
		 jne .maybeLODSW
		 writeln strLODSB
		 crlf
		 jmp .end
		 
		 .maybeLODSW						;LODSW
		 cmp al, 0xAD
		 jne .maybeSTOSB
		 writeln strLODSW
		 crlf
		 jmp .end
		 
		 .maybeSTOSB							;STOSB
		 cmp al, 0xAA
		 jne .maybeSTOSW
		 writeln strSTOSB
		 crlf
		 jmp .end
		 
		 .maybeSTOSW						;STOSW
		 cmp al, 0xAB
		 jne .maybeNOP
		 writeln strSTOSW
		 crlf
		 jmp .end
		 
		 .maybeNOP								;NOP
		 cmp al, 0x90
		 jne .maybeConditionalJump
		 writeln strNOP
		 crlf
		 jmp .end
		 
		 ;--------------------------END OF ONE BYTE INSTRUCTIONS---------------------
		 ;--------------------------START OF CONDITIONAL JUMP (xcpt JCXZ)---------
		 
		 .maybeConditionalJump			
		 mov cl, al									
		 and cl, 0x70
		 cmp cl, 0x70
		 jne .maybeRETWithin
		 
		 .maybeJE									;JE
		 cmp al, 0x74
		 jne .maybeJL
		 writeln strJE
		 jmp .getDisplacementByte
		 
		 .maybeJL									;JL
		 cmp al, 0x7C
		 jne .maybeJLE
		 writeln strJL
		 jmp .getDisplacementByte
		 
		 .maybeJLE								;JLE
		 cmp al, 0x7E
		 jne .maybeJB
		 writeln strJLE
		 jmp .getDisplacementByte
		 
		 .maybeJB									;JB
		 cmp al, 0x72
		 jne .maybeJBE
		 writeln strJB
		 jmp .getDisplacementByte
			
		 .maybeJBE								;JBE				
		 cmp al, 0x76
		 jne .maybeJP
		 writeln strJBE
		 jmp .getDisplacementByte
		 
		 .maybeJP									;JP
		 cmp al, 0x7A
		 jne .maybeJO
		 writeln strJP
		 jmp .getDisplacementByte
		 
		 .maybeJO									;JO
		 cmp al, 0x70
		 jne .maybeJS
		 writeln strJO
		 jmp .getDisplacementByte
		 
		 .maybeJS									;JS
		 cmp al, 0x78
		 jne .maybeJNE
		 writeln strJS
		 jmp .getDisplacementByte
		 
		 .maybeJNE								;JNE
		 cmp al, 0x75
		 jne .maybeJGE
		 writeln strJNE
		 jmp .getDisplacementByte
		 
		 .maybeJGE								;JGE
		 cmp al, 0x7D
		 jne .maybeJG
		 writeln strJGE
		 jmp .getDisplacementByte
		 
		 .maybeJG									;JG
		 cmp al, 0x7F
		 jne .maybeJAE
		 writeln strJG
		 jmp .getDisplacementByte
		 
		 .maybeJAE								;JAE
		 cmp al, 0x73
		 jne .maybeJA
		 writeln strJAE
		 jmp .getDisplacementByte
		 
		 .maybeJA									;JA
		 cmp al, 0x77
		 jne .maybeJPO
		 writeln strJA
		 jmp .getDisplacementByte
		 
		 .maybeJPO								;JPO
		 cmp al, 0x7B
		 jne .maybeJNO
		 writeln strJPO
		 jmp .getDisplacementByte
		 
		 .maybeJNO								;JNO
		 cmp al, 0x71
		 jne .maybeJNS
		 writeln strJNO
		 jmp .getDisplacementByte
		 
		 .maybeJNS								;JNS
		 cmp al, 0x79
		 jne .maybeRETWithin
		 writeln strJNS
		 jmp .getDisplacementByte
		 
		 ;-------------------------------END OF CONDITIONAL JUMP (xcpt JCXZ)-----------------------------------
		 ;-------------------------------STAR OF RET----------------------------------------------------------------------------
		  
		 .maybeRETWithin
		 cmp al, 0xC2
		 jne .maybeRETInter
		 writeln strRET
		 readNext 2
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .maybeRETInter
		 cmp al, 0xCA
		 jne .maybeINT
		 writeln strRETF
		 readNext 2
		 call putHexStr
		 crlf
		 jmp .end
		 
		 ;-------------------------------END OF RET---------------------------------------------------
		 ;-------------------------------INT-----------------------------------------------------------------
		 .maybeINT
		 cmp al, 0xCD
		 jne .maybeJMPdirect
		 writeln strINT
		 readNext 1
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 
		 ;-------------------------------INT-------------------------------------------------------------------
		 ;<<<<<<<<<<< 4. READ FILE. UNCON JUMP REDIRECTION>>>>>>>>>>>>>;
		 ;-------------------------------START OF UNCONDITIONAL JUMP-------------------
		 
		 .maybeJMPdirect
		 cmp al, 0xE9
		 jne .maybeJMPdirectShort
		 writeln strJMP
		 readNext 2
		 call getDispWord				
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .maybeJMPdirectShort
		 cmp al, 0xEB
		 jne .maybeJMPdirectInterseg
		 writeln strJMP
		 jmp .getDisplacementByte
		 
		 .maybeJMPdirectInterseg
		 cmp al, 0xEA
		 jne .maybeJMPindirectWithSeg	
		 writeln strJMP
		 readNext 2
		 mov [savedWord], ax		;save IP
		 readNext 2						;get CS
		 call putHexStr
		 writeln colon
		 mov ax, [savedWord]
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .maybeJMPindirectWithSeg								;<- naudoju ir indirect jumpam. Iš principo tas pats, bet gali būt error'u vėliau 
		 cmp al, 0xFE
		 jb .maybeCALLdirectWithSeg
		 mov W, 0x01
		 cmp al, 0xFF
		 je .willBeFF
		 mov W, 0x00
		 .willBeFF
		 readNext 1
		 call getAddressByteInfo
		 cmp REG, 0x04							
		 je .JMPindirectSeg
		 cmp REG, 0x05						    
		 je .JMPindirectInter
		 cmp REG, 0x02						    
		 je .maybeCALLindirectWithSeg
		 cmp REG, 0x03							
		 je .maybeCALLindirectInter
		 cmp REG, 0x01
		 je .DECRegMem
		 cmp REG, 0x00
		 je .INCRegMem
		 mov W, 0xFF
		 cmp REG, 0x06
		 je .PUSHRegMem
		 jmp .maybeCALLdirectWithSeg
		 
		 .JMPindirectSeg
		 writeln strJMP
		 cmp MD, 0x03
		 je .noWordPtr_0
		 writeln strWPTR
		 .noWordPtr_0
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 .JMPindirectInter
		 writeln strJMP
		 writeln strFAR
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 ;-------------------------------END OF UNCONDITIONAL JUMP-------------------------
		 ;-------------------------------START OF CALL-------------------------------------------------
		 
		 .maybeCALLindirectWithSeg
		 writeln strCALL
		 cmp MD, 0x03
		 je .noWordPtr_1
		 writeln strWPTR
		 .noWordPtr_1
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 .maybeCALLindirectInter
		 writeln strCALL
		 writeln strFAR
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 .maybeCALLdirectWithSeg
		 cmp al, 0xE8
		 jne .maybeCALLdirectInter
		 writeln strCALL
		 readNext 2
		 call getDispWord
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .maybeCALLdirectInter				
		 cmp al, 0x9A
		 jne .maybeLogicalAndArithmeticDistribution
		 writeln strCALL
		 readNext 2
		 mov [savedWord], ax		;save IP
		 readNext 2						;get CS
		 call putHexStr
		 writeln colon
		 mov ax, [savedWord]
		 call putHexStr
		 crlf
		 jmp .end
		 
		  ;-------------------------------END OF CALL---------------------------------------------------
		  ;<<<<<<<<<<< 5. READ FILE. XOR REDIRECTION >>>>>>>>>>>>>;
		  ;-------------------------------START OF XOR-----------------------------------------------
		  ;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;
		 .maybeLogicalAndArithmeticDistribution
		 mov W, 0x00
		 mov BYTE_READ, 0x01
		 cmp al, 0x80
		 je .yesLogArit
		 mov W, 0x01
		 mov BYTE_READ, 0x02
		 cmp al, 0x81
		 je .yesLogArit
		 mov W, 0x00
		 mov BYTE_READ, 0x01
		 cmp al, 0x82
		 je .yesLogArit
		 mov W, 0x01
		 mov BYTE_READ, 0x02
		 je .yesLogArit
		 cmp al, 0x83
		 je .yesLogArit
		 mov W, 0xFF
		 mov BYTE_READ, 0x00
		 jmp .maybeXORImmedToAL
		 .yesLogArit
		 mov S_W, al
		 readNext 1
		 call getAddressByteInfo
		 cmp REG, 0x06
		 je .XORImmedToRegMem
		 cmp REG, 0x01
		 je .ORImmedToRegMem
		 cmp REG, 0x04
		 je .ANDImmedToRegMem
		 cmp REG, 0x07
		 je .CMPImmedToRegMem
		 cmp REG, 0x03
		 je .SBBImmedToRegMem
		 cmp REG, 0x05
		 je .SUBImmedToRegMem
		 cmp REG, 0x02
		 je .ADCImmedToRegMem
		 cmp REG, 0x00
		 je .ADDImmedToRegMem
		 jmp .end
		 ;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;
		 
		 .maybeXORImmedToAL
		 cmp al, 0x34
		 jne .maybeXORImmedToAX
		 readNext 1
		 writeln strXOR
		 writeln [halfRegisters]
		 writeln comma
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 .maybeXORImmedToAX
		 cmp al, 0x35
		 jne .maybeXORRegMemAndRegEither
		 readNext 2
		 writeln strXOR
		 writeln [fullRegisters]
		 writeln comma
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .XORImmedToRegMem
		 writeln strXOR
		 mov V_W, 0xFF
		 call formInstrWB
		 writeln comma
		 readNext BYTE_READ
		 cmp BYTE_READ, 0x02
		 je .byte_read2_1
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 .byte_read2_1
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .maybeXORRegMemAndRegEither
		 cmp al, 0x30
		 jb .maybeORImmedToAL
		 cmp al, 0x33
		 ja .maybeORImmedToAL
		 writeln strXOR
		 mov D_W, al
		 and D_W, 0x03
		 readNext 1
		 call getAddressByteInfo
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 ;-------------------------------END OF XOR-----------------------------------------------
		 ;-------------------------------START OF OR---------------------------------------------
		 .maybeORImmedToAL
		 cmp al, 0x0C
		 jne .maybeORImmedToAX
		 readNext 1
		 writeln strOR
		 writeln [halfRegisters]
		 writeln comma
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 .maybeORImmedToAX
		 cmp al, 0x0D
		 jne .maybeORRegMemAndRegEither
		 readNext 2
		 writeln strOR
		 writeln [fullRegisters]
		 writeln comma
		 call putHexStr
		 crlf
		 jmp .end
		 
		 
		 .ORImmedToRegMem
		 writeln strOR
		 mov V_W, 0xFF
		 call formInstrWB
		 writeln comma
		 readNext BYTE_READ
		 cmp BYTE_READ, 0x02
		 je .byte_read2_2
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 .byte_read2_2
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .maybeORRegMemAndRegEither
		 cmp al, 0x08
		 jb .maybeTESTImmedToAL
		 cmp al, 0x0B
		 ja .maybeTESTImmedToAL
		 writeln strOR
		 mov D_W, al
		 and D_W, 0x03
		 readNext 1
		 call getAddressByteInfo
		 call formInstrCode
		 crlf
		 jmp .end
		 ;-------------------------------END OF OR---------------------------------------------
		 ;<<<<<<<<<<< 6. READ FILE. TEST REDIRECTION >>>>>>>>>>>>>;
		 ;-------------------------------START OF TEST--------------------------------------
		 
		 .maybeTESTImmedToAL
		 cmp al, 0xA8
		 jne .maybeTESTImmedToAX
		 readNext 1
		 writeln strTEST
		 writeln [halfRegisters]
		 writeln comma
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 .maybeTESTImmedToAX
		 cmp al, 0xA9
		 jne .maybeTESTImmedToRegMem
		 readNext 2
		 writeln strTEST
		 writeln [fullRegisters]
		 writeln comma
		 call putHexStr
		 crlf
		 jmp .end
		 
		 
		 .maybeTESTImmedToRegMem
		 mov W, 0x00
		 mov BYTE_READ, 0x01
		 cmp al, 0xF6
		 je .checkToTEST
		 mov W, 0x01
		 mov BYTE_READ, 0x02
		 cmp al, 0xF7
		 je .checkToTEST
		 mov W, 0x00
		 mov BYTE_READ, 0x00
		 jmp .maybeTESTRegMemAndRegEither
		 .checkToTEST
		 readNext 1
		 call getAddressByteInfo
		 cmp REG, 0x00
		 je .TEST
		 cmp REG, 0x02
		 je .NOT
		 cmp REG, 0x07
		 je .IDIV
		 cmp REG, 0x06
		 je .DIV
		 cmp REG, 0x05
		 je .IMUL
		 cmp REG, 0x04
		 je .MUL
		 cmp REG, 0x03
		 je .NEG
		 ;--
		 .TEST
		 writeln strTEST
		 mov V_W, 0xFF
		 call formInstrWB
		 writeln comma
		 readNext BYTE_READ
		 cmp BYTE_READ, 0x02
		 je .byte_read2_3
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 .byte_read2_3
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .maybeTESTRegMemAndRegEither
		 mov D_W, 0x00
		 mov BYTE_READ, 0x01
		 cmp al, 0x84
		 je .furtherTEST
		 mov D_W, 0x01
		 mov BYTE_READ, 0x02
		 cmp al, 0x85
		 jne .maybeANDImmedToAL
		 .furtherTEST
		 writeln strTEST
		 readNext 1
		 call getAddressByteInfo
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 ;-------------------------------END OF TEST--------------------------------------
		 ;-------------------------------START OF AND------------------------------------
		 
		 .maybeANDImmedToAL
		 mov W, 0xFF
		 mov BYTE_READ, 0x00
		 cmp al, 0x24
		 jne .maybeANDImmedToAX
		 readNext 1
		 writeln strAND
		 writeln [halfRegisters]
		 writeln comma
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 .maybeANDImmedToAX
		 cmp al, 0x25
		 jne .maybeANDRegMemAndRegEither
		 readNext 2
		 writeln strAND
		 writeln [fullRegisters]
		 writeln comma
		 call putHexStr
		 crlf
		 jmp .end
		 
		 
		 .ANDImmedToRegMem
		 writeln strAND
		 mov V_W, 0xFF
		 call formInstrWB
		 writeln comma
		 readNext BYTE_READ
		 cmp BYTE_READ, 0x02
		 je .byte_read2_4
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 .byte_read2_4
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .maybeANDRegMemAndRegEither
		 cmp al, 0x20
		 jb .maybeVariousShifts
		 cmp al, 0x23
		 ja .maybeVariousShifts
		 writeln strAND
		 mov D_W, al
		 and D_W, 0x03
		 readNext 1
		 call getAddressByteInfo
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 ;-------------------------------END OF AND------------------------------------
		 ;-------------------------------START OF VARIOUS SHIFTS------------------------------------
		 .maybeVariousShifts
		 cmp al, 0xD0
		 jb .maybeCMPImmedToAL
		 cmp al, 0xD3
		 ja .maybeCMPImmedToAL
		 mov W, 0x00
		 mov V_W, al
		 and V_W, 0x03
		 readNext 1
		 call getAddressByteInfo
		 push di
		 push cx
	     mov al, REG
		 mov cl, 0x08
		 mul cl
		 mov ah, 0
		 mov di, ax
		 pop cx
		 writeln [logicCommands + di]
		 pop di
		 call formInstrWB
		 crlf
		 jmp .end
		 
		 .NOT
		 writeln strNOT
		 mov V_W, 0xFF
		 call formInstrWB
		 crlf
		 jmp .end
		 
		 ;-------------------------------END OF VARIOUS SHIFTS------------------------------------
		 ;-------------------------------START OF DIVISION AND MULTIPLICATION------------------------------------
		 .IDIV
		 writeln strIDIV
		 mov V_W, 0xFF
		 call formInstrWB
		 crlf
		 jmp .end
		 
		 .DIV
		 writeln strDIV
		 mov V_W, 0xFF
		 call formInstrWB
		 crlf
		 jmp .end
		 
		 .IMUL
		 writeln strIMUL
		 mov V_W, 0xFF
		 call formInstrWB
		 crlf
		 jmp .end
		 
		 
		 .MUL
		 writeln strMUL
		 mov V_W, 0xFF
		 call formInstrWB
		 crlf
		 jmp .end
		 
		 ;-------------------------------END OF DIVISION AND MULTIPLICATION------------------------------------
		 ;-------------------------------START OF COMPARE-----------------------------------------------------------------
		 
		 .maybeCMPImmedToAL
		 cmp al, 0x3C
		 jne .maybeCMPImmedToAX
		 readNext 1
		 writeln strCMP
		 writeln [halfRegisters]
		 writeln comma
		 call putHexStr
		 crlf
		 jmp .end
		 .maybeCMPImmedToAX
		 cmp al, 0x3D
		 jne .maybeCMPRegMemAndRegEither
		 readNext 2
		 writeln strCMP
		 writeln [fullRegisters]
		 writeln comma
		 call putHexStr
		 crlf
		 jmp .end
		 
		 
		 .CMPImmedToRegMem
		 writeln strCMP
		 and S_W, 0x03
		 mov V_W, 0xFF
		 call formInstrWB	
		 mov BYTE_READ, 0x02
		 cmp S_W, 0x01
		 je .read2Bytes_1
		 mov BYTE_READ, 0x01
		 .read2Bytes_1
		 writeln comma
		 cmp S_W, 0x03
		 jne .dontNeedPlus_1
		 writeln plus
		 .dontNeedPlus_1
		 readNext BYTE_READ
		 cmp BYTE_READ, 0x02
		 je .byte_read2_5
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 .byte_read2_5
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .maybeCMPRegMemAndRegEither
		 cmp al, 0x38
		 jb .maybeSBBImmedToAL
		 cmp al, 0x3B
		 ja .maybeSBBImmedToAL
		 writeln strCMP
		 mov D_W, al
		 and D_W, 0x03
		 readNext 1
		 call getAddressByteInfo
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 ;-------------------------------END OF COMPARE-----------------------------------------------------------------
		 ;-------------------------------START OF SUBTRACT WITH BORROW------------------------------------
		 
		 .maybeSBBImmedToAL
		 cmp al, 0x1C
		 jne .maybeSBBImmedToAX
		 readNext 1
		 writeln strSBB
		 writeln [halfRegisters]
		 writeln comma
		 call putHexStr
		 crlf
		 jmp .end
		 .maybeSBBImmedToAX
		 cmp al, 0x1D
		 jne .maybeSBBRegMemAndRegEither
		 readNext 2
		 writeln strSBB
		 writeln [fullRegisters]
		 writeln comma
		 call putHexStr
		 crlf
		 jmp .end
		 
		 
		 .SBBImmedToRegMem
		 writeln strSBB
		 and S_W, 0x03
		 mov V_W, 0xFF
		 call formInstrWB
		 mov BYTE_READ, 0x02
		 cmp S_W, 0x01
		 je .read2Bytes_2
		 mov BYTE_READ, 0x01
		 .read2Bytes_2
		 writeln comma
		 cmp S_W, 0x03
		 jne .dontNeedPlus_2
		 writeln plus
		 .dontNeedPlus_2
		 readNext BYTE_READ
		 cmp BYTE_READ, 0x02
		 je .byte_read2_6
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 .byte_read2_6
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .maybeSBBRegMemAndRegEither
		 cmp al, 0x18
		 jb .maybeSUBImmedToAL
		 cmp al, 0x1B
		 ja .maybeSUBImmedToAL
		 writeln strSBB
		 mov D_W, al
		 and D_W, 0x03
		 readNext 1
		 call getAddressByteInfo
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 ;-------------------------------END OF SUBTRACT WITH BORROW------------------------------------
		 ;-------------------------------START OF SUBTRACT---------------------------------------------------------
		 
		 .maybeSUBImmedToAL
		 cmp al, 0x2C
		 jne .maybeSUBImmedToAX
		 readNext 1
		 writeln strSUB
		 writeln [halfRegisters]
		 writeln comma
		 call putHexStr
		 crlf
		 jmp .end
		 .maybeSUBImmedToAX
		 cmp al, 0x2D
		 jne .maybeSUBRegMemAndRegEither
		 readNext 2
		 writeln strSUB
		 writeln [fullRegisters]
		 writeln comma
		 call putHexStr
		 crlf
		 jmp .end
		 
		 
		 .SUBImmedToRegMem
		 writeln strSUB
		 and S_W, 0x03
		 mov V_W, 0xFF
		 call formInstrWB
		 mov BYTE_READ, 0x02
		 cmp S_W, 0x01
		 je .read2Bytes_3
		 mov BYTE_READ, 0x01
		 .read2Bytes_3
		 writeln comma
		 cmp S_W, 0x03
		 jne .dontNeedPlus_3
		 writeln plus
		 .dontNeedPlus_3
		 readNext BYTE_READ
		 cmp BYTE_READ, 0x02
		 je .byte_read2_7
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 .byte_read2_7
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .maybeSUBRegMemAndRegEither
		 cmp al, 0x28
		 jb .maybeADCImmedToAL
		 cmp al, 0x2B
		 ja .maybeADCImmedToAL
		 writeln strSUB
		 mov D_W, al
		 and D_W, 0x03
		 readNext 1
		 call getAddressByteInfo
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 ;-------------------------------END OF SUBTRACT---------------------------------------------------------
		 ;-------------------------------START OF ADD WITH CARRY-------------------------------------------
		 
		 .maybeADCImmedToAL
		 cmp al, 0x14
		 jne .maybeADCImmedToAX
		 readNext 1
		 mov ah, 0
		 writeln strADC
		 writeln [halfRegisters]
		 writeln comma
		 call putHexStr
		 crlf
		 jmp .end
		 .maybeADCImmedToAX
		 cmp al, 0x15
		 jne .maybeADCRegMemAndRegEither
		 readNext 2
		 writeln strADC
		 writeln [fullRegisters]
		 writeln comma
		 call putHexStr
		 crlf
		 jmp .end
		 
		 
		 .ADCImmedToRegMem
		 writeln strADC
		 and S_W, 0x03
		 call formInstrWB
		 mov BYTE_READ, 0x02
		 cmp S_W, 0x01
		 je .read2Bytes_4
		 mov BYTE_READ, 0x01
		 .read2Bytes_4
		 writeln comma
		 cmp S_W, 0x03
		 jne .dontNeedPlus_4
		 writeln plus
		 .dontNeedPlus_4
		 readNext BYTE_READ
		 cmp BYTE_READ, 0x02
		 je .byte_read2_8
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 .byte_read2_8
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .maybeADCRegMemAndRegEither
		 cmp al, 0x10
		 jb .maybeADDImmedToAL
		 cmp al, 0x13
		 ja .maybeADDImmedToAL
		 writeln strADC
		 mov D_W, al
		 and D_W, 0x03
		 readNext 1
		 call getAddressByteInfo
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 ;-------------------------------END OF ADD WITH CARRY-------------------------------------------
		 ;-------------------------------START OF ADD------------------------------------------------------------
		 
		 .maybeADDImmedToAL
		 cmp al, 0x04
		 jne .maybeADDImmedToAX
		 readNext 1
		 mov ah, 0
		 writeln strADD
		 writeln [halfRegisters]
		 writeln comma
		 call putHexStr
		 crlf
		 jmp .end
		 .maybeADDImmedToAX
		 cmp al, 0x05
		 jne .maybeADDRegMemAndRegEither
		 readNext 2
		 writeln strADD
		 writeln [fullRegisters]
		 writeln comma
		 call putHexStr
		 crlf
		 jmp .end
		 
		 
		 .ADDImmedToRegMem
		 writeln strADD
		 and S_W, 0x03
		 call formInstrWB
		 mov BYTE_READ, 0x02
		 cmp S_W, 0x01
		 je .read2Bytes_5
		 mov BYTE_READ, 0x01
		 .read2Bytes_5
		 writeln comma
		 cmp S_W, 0x03
		 jne .dontNeedPlus_5
		 writeln plus
		 .dontNeedPlus_5
		 readNext BYTE_READ
		 cmp BYTE_READ, 0x02
		 je .byte_read2_9
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 .byte_read2_9
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .maybeADDRegMemAndRegEither
		 cmp al, 0x00
		 jb .maybeDECReg
		 cmp al, 0x03
		 ja .maybeDECReg
		 writeln strADD
		 mov D_W, al
		 and D_W, 0x03
		 readNext 1
		 call getAddressByteInfo
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 ;-------------------------------END OF ADD------------------------------------------------------------
		 ;-------------------------------START OF DECREMENT, INCREMENT AND NEGATE---------------------
		 
		 .maybeDECReg
		 mov REG, al
		 and REG, 0xF8
		 cmp REG, 0x48
		 jne .maybeINCReg
		 writeln strDEC
		 push di
		 push cx
		 and ax, 0x0007
		 mov cl, 0x08
		 mul cl
		 mov di, ax
		 pop cx
		 writeln [fullRegisters + di]
		 pop di
		 crlf
		 jmp .end
		 
		 .DECRegMem
		 writeln strDEC
		 mov V_W, 0xFF
		 call formInstrWB
		 crlf
		 jmp .end
		 
		 .NEG
		 writeln strNEG
		 mov V_W, 0xFF
		 call formInstrWB
		 crlf
		 jmp .end
		 
		 .INCRegMem
		 writeln strINC
		 mov V_W, 0xFF
		 call formInstrWB
		 crlf
		 jmp .end
		 
		 .maybeINCReg
		 mov REG, al
		 and REG, 0xF8
		 cmp REG, 0x40
		 jne .maybeLEA
		 writeln strINC
		 push di
		 push cx
		 and ax, 0x0007
		 mov cl, 0x08
		 mul cl
		 mov di, ax
		 pop cx
		 writeln [fullRegisters + di]
		 pop di
		 crlf
		 jmp .end
		 
		 ;-------------------------------END OF DECREMENT, INCREMENT AND NEGATE---------------------
		 ;-------------------------------START OF LOAD------------------------------------------------------------------------
		 
		 .maybeLEA
		 cmp al, 0x8D
		 jne .maybeLDS
		 writeln strLEA
		 readNext 1
		 call getAddressByteInfo
		 mov D_W, 0x03
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 .maybeLDS
		 cmp al, 0xC5
		 jne .maybeLES
		 writeln strLDS
		 readNext 1
		 call getAddressByteInfo
		 mov D_W, 0x03
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 .maybeLES
		 cmp al, 0xC4
		 jne .maybeOUTVar
		 writeln strLES
		 readNext 1
		 call getAddressByteInfo
		 mov D_W, 0x03
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 ;-------------------------------END OF LOAD------------------------------------------------------------------------
		 ;<<<<<<<<<<< 7. READFILE. END OF ARITHMETIC AND LOGICAL >>>>>>>>>>>>>;
		 ;-------------------------------START OF IN AND OUT-----------------------------------------------------------
		 
		 .maybeOUTVar
		 cmp al, 0xEE
		 jne .maybeEF
		 writeln strOUT
		 writeln regDX
		 writeln comma
		 writeln regAL
		 crlf
		 jmp .end
		 .maybeEF
		 cmp al, 0xEF
		 jne .maybeOUTFixed
		 writeln strOUT
		 writeln regDX
		 writeln comma
		 writeln regAX
		 crlf
		 jmp .end
		 
		 .maybeOUTFixed
		cmp al, 0xE6
		jne .maybeE7
		writeln strOUT
		readNext 1
		mov ah, 0
		call putHexStr
		writeln comma
		writeln [halfRegisters]
		crlf
		jmp .end
		.maybeE7
		cmp al, 0xE7
		jne .maybeINVar
		writeln strOUT
		readNext 1
		mov ah, 0
		call putHexStr
		writeln comma
		writeln [fullRegisters]
		crlf
		jmp .end
		
		 .maybeINVar
		 cmp al, 0xEC
		 jne .maybeEC
		 writeln strIN
		 writeln regAL
		 writeln comma
		 writeln regDX
		 crlf
		 jmp .end
		 .maybeEC
		 cmp al, 0xED
		 jne .maybeINFixed
		 writeln strIN
		 writeln regAX
		 writeln comma
		 writeln regDX
		 crlf
		 jmp .end
		 
		 .maybeINFixed
		 cmp al, 0xE4
	 	 jne .maybeE5
		 writeln strIN
		 writeln [halfRegisters]
	     writeln comma
		 readNext 1
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 .maybeE5
		 cmp al, 0xE5
		 jne .maybeXCHGToAX
		 writeln strIN
		 writeln [fullRegisters]
		 writeln comma
		 readNext 1
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		
		 ;-------------------------------END OF IN AND OUT-----------------------------------------------------------
		 ;-------------------------------START OF EXCHANGE--------------------------------------------------------
		 
		 .maybeXCHGToAX
		 cmp al, 0x90
		 jb .maybeXCHGRegMemWithReg
		 cmp al, 0x97
		 ja .maybeXCHGRegMemWithReg
		 push di
		 push cx
		 and ax, 0x0007
		 mov cl, 0x08
		 mul cl
		 mov di, ax
		 writeln strXCHG
		 writeln regAX
		 writeln comma
		 writeln [fullRegisters + di]
		 pop cx
		 pop di
		 crlf
		 jmp .end
		 
		 .maybeXCHGRegMemWithReg
		 mov D_W, 0x02
		 mov BYTE_READ, 0x01
		 cmp al, 0x86
		 je .furtherXCHG
		 mov D_W, 0x03
		 mov BYTE_READ, 0x02
		 cmp al, 0x87
		 jne .maybePOPSegment
		 .furtherXCHG
		 writeln strXCHG
		 readNext 1
		 call getAddressByteInfo
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 ;-------------------------------END OF EXCHANGE--------------------------------------------------------
		 ;-------------------------------START OF POP---------------------------------------------------------------
		 
		 .maybePOPSegment
		 mov REG, al
		 and REG, 0xE7
		 cmp REG, 0x07
		 jne .maybePOPRegister
		 writeln strPOP
		 mov ah, 0
		 shr ax, 0x03
		 push di
		 push cx
		 mov cl, 0x08
		 mul cl
		 mov di, ax
		 writeln [segments + di]
		 crlf
		 pop cx
		 pop di
		 jmp .end
		 
		 .maybePOPRegister
		 cmp al, 0x58
		 jb .maybePOPRegMem
		 cmp al, 0x5F
		 ja .maybePOPRegMem
		 push di
		 push cx
		 and ax, 0x0007
		 mov cl, 0x08
		 mul cl
		 mov di, ax
		 writeln strPOP
		 writeln [fullRegisters + di]
		 pop cx
		 pop di
		 crlf
		 jmp .end
		 
		 .maybePOPRegMem
		 cmp al, 0x8F
		 jne .maybePUSHSegment
		 writeln strPOP
		 readNext 1
		 call getAddressByteInfo
		 mov V_W, 0x03
		 call formInstrWB
		 crlf
		 jmp .end

		 ;-------------------------------END OF POP---------------------------------------------------------------
		 ;-------------------------------START OF PUSH---------------------------------------------------------
		 
		 .maybePUSHSegment
		 mov REG, al
		 and REG, 0xE6							
		 cmp REG, 0x06
		 jne .maybePUSHRegister
		 writeln strPUSH
		 mov ah, 0
		 shr ax, 0x03
		 push di
		 push cx
		 mov cl, 0x08
		 mul cl
		 mov di, ax
		 writeln [segments + di]
		 crlf
		 pop cx
		 pop di
		 jmp .end
		 
		 .maybePUSHRegister
		 cmp al, 0x50
		 jb .maybeMOVRegMemToFromReg
		 cmp al, 0x57
		 ja .maybeMOVRegMemToFromReg
		 push di
		 push cx
		 and ax, 0x0007
		 mov cl, 0x08
		 mul cl
		 mov di, ax
		 writeln strPUSH
		 writeln [fullRegisters + di]
		 pop cx
		 pop di
		 crlf
		 jmp .end
		 
		 .PUSHRegMem
		 writeln strPUSH
		 mov V_W, 0x03
		 call formInstrWB
		 crlf
		 jmp .end
		 
		 ;-------------------------------END OF PUSH---------------------------------------------------------
		 ;-------------------------------START OF MOV---------------------------------------------------------
		 
		 .maybeMOVRegMemToFromReg
		 cmp al, 0x88
		 jb .maybeMOVImmedToRegMem
		 cmp al, 0x8B
		 ja .maybeMOVImmedToRegMem
		 writeln strMOV
		 mov D_W, al
		 and D_W, 0x03
		 readNext 1
		 call getAddressByteInfo
		 call formInstrCode
		 crlf
		 jmp .end
		 
		 .maybeMOVImmedToRegMem
		 mov W, 0x00
		 mov BYTE_READ, 0x01
		 cmp al, 0xC6
		 je .MOVC
		 mov W, 0x01
		 mov BYTE_READ, 0x02
		 cmp al, 0xC7
		 jne .maybeMOVImmedToReg
		 .MOVC
		 writeln strMOV
		 readNext 1
		 call getAddressByteInfo
		 call formInstrWB
		 writeln comma
		 readNext BYTE_READ
		 cmp BYTE_READ, 0x02
		 je .byte_read2_I
		 mov ah, 0
		 call putHexStr
		 crlf
		 jmp .end
		 .byte_read2_I
		 call putHexStr
		 crlf
		 jmp .end
		 
		 .maybeMOVImmedToReg
		 cmp al, 0xB0
		 jb .maybeMOVMemToAccum
		 cmp al, 0xBF
		 ja .maybeMOVMemToAccum
		 writeln strMOV
		 push di
		 push cx
		 mov W, al
		 shr W, 3
		 and W, 0x01
		 and al, 0x07
		 mov cl, 0x08
		 mul cl
		 mov di, ax
		 cmp W, 0x01
		 je .beWORD
		 writeln [halfRegisters + di]
		 writeln comma
		 readNext 1
		 mov ah, 0
		 call putHexStr
		 pop cx
		 pop di
		 crlf
		 jmp .end
		 .beWORD
		 writeln [fullRegisters + di]
		 writeln comma
		 readNext 2
		 call putHexStr
		 crlf
		 pop cx
		 pop di
		 jmp .end
		 
		 .maybeMOVMemToAccum
		 mov W, 0xFF
		 cmp al, 0xA0
		 jne .maybeA1
		 writeln strMOV
		 writeln regAL
		 writeln comma
		 readNext 2
		 writeln leftSquareBracket
		 call putHexStr
		 writeln rightSquareBracket
		 crlf
		 jmp .end
		 .maybeA1
		 cmp al, 0xA1
		 jne .maybeMOVAccumToMem
		 writeln strMOV
		 writeln regAX
		 writeln comma
		 readNext 2
		 writeln leftSquareBracket
		 call putHexStr
		 writeln rightSquareBracket
		 crlf
		 jmp .end
		 
		 .maybeMOVAccumToMem
		 mov W, 0xFF
		 cmp al, 0xA2
		 jne .maybeA3
		 writeln strMOV
		 readNext 2
		 writeln leftSquareBracket
		 call putHexStr
		 writeln rightSquareBracket
		 writeln comma
		 writeln regAL
		 crlf
		 jmp .end
		 .maybeA3
		 cmp al, 0xA3
		 jne .maybeMOVRegMemToSegment
		 writeln strMOV
		 readNext 2
		 writeln leftSquareBracket
		 call putHexStr
		 writeln rightSquareBracket
		 writeln comma
		 writeln regAX
		 crlf
		 jmp .end
		 
		 .maybeMOVRegMemToSegment
		 cmp al, 0x8E
		 jne .maybeMOVSegmentRegToMem
		 writeln strMOV
		 readNext 1
		 call getAddressByteInfo
		 push di
		 push cx
		 mov al, REG
		 mov cl, 0x08
		 mul cl
		 mov di, ax
		 writeln [segments + di]
		 writeln comma
		 mov V_W, 0x03
		 call formInstrWB
		 crlf
		 pop cx
		 pop di
		 jmp .end
		 
		 .maybeMOVSegmentRegToMem
		 mov D_W, 0xFF
		 cmp al, 0x8C
		 jne .printDB
		 writeln strMOV
		 readNext 1
		 call getAddressByteInfo
		 push di
		 push cx
		 mov al, REG
		 mov cl, 0x08
		 mul cl
		 mov di, ax
		 mov V_W, 0x03
		 call formInstrWB
		 writeln comma
		 writeln [segments + di]
		 crlf
		 pop cx
		 pop di
		 jmp .end
		 
		 ;-------------------------------END OF MOV---------------------------------------------------------
		 ;-------------------------------END OF ORIGINAL x8086 INSTRUCTIONS--------------
		 
         ;......
		 
		.getDisplacementByte
		readNext 1
		call getDispByte
		call putHexStr
		crlf
		jmp .end


         .printDB:
         call putHexStr                		; DB
         mov [takenArgument],  ax
         writeln strDB
		 crlf
         
         .end
		 jmp .goAgain						; Loop until no more to read
		 
	 .goToEnd
	 clc
	 add sp, 20
	 pop bp
	 pop si
	 pop dx
	 pop cx
	 pop bx
	 pop ax
ret 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;<<<<<<<<<<< 8. GET ADDRESS BYTE, DISP BYTE AND DISP WORD >>>>>>>>>>>>>;
getAddressByteInfo	
; Parse the address byte for mod, reg, r/m

	mov MD, al
	and MD, 0xC0
	shr MD, 6
	
	mov REG, al
	and REG, 0x38
	shr REG, 3
	
	mov RM, al
	and RM, 0x07
	
ret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
getDispByte:
	; Get byte displacement
	; AL - brought byte operand
	push cx
	
	cmp al, 0x80
	jb .dontNegate
	neg al
	mov cx, [lseek]
	sub cx, ax
	mov ax, cx
	jmp .skip
	
	.dontNegate:
	mov ah, 0
	add ax, [lseek]
	
	.skip:
	pop cx
	ret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
getDispWord:
	; Get word displacement
	; AX - brought word operand
	push cx
	
	cmp ax, 0x8000
	jb .dontNegate
	neg ax
	mov cx, [lseek]
	sub cx, ax
	mov ax, cx
	jmp .skip
	
	.dontNegate:
	add ax, [lseek]
	
	.skip:
	pop cx
ret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;<<<<<<<<<<< 9. FORM THE INSTRUCTION W/O WRD, BYTE PTR >>>>>>>>>>>>>;
formInstrCode:
	; Form the rest of the instruction
	; AL - instruction byte
	push di
	push ax
	push cx
	
	cmp MD, 0x03					;check mod11
	je .mod11
	cmp MD, 0x02					;check mod10
	je .mod10
	cmp MD, 0x01					;check mod01
	je .mod01
	
	.mod00								;else mod 00
	cmp RM, 0x06
	jne .notRm110					;if mod = 00 and r/m = 110
	mov BYTE_NUM, 0x02
	jmp .getRegisterName
	.notRm110							
	jmp .getRegisterName
	
	.mod11:
	mov BYTE_NUM, 0x01	
	jmp .getRegisterName
	
	.mod10:
	mov BYTE_NUM, 0x02
	jmp .getRegisterName		
	
	.mod01:
	mov BYTE_NUM, 0x01
	jmp .getRegisterName
	
	.getRegisterName:					; access the string in the string arrays holding the names of register
	mov al, RM									
	mov cl, 0x08
	mul cl
	mov di, ax
	mov al, REG
	mul cl
	mov [savedWord], ax
	
	cmp MD, 0x03							;if mod = 11 then just print register name
	je .printMod11
	cmp MD, 0						
	jne .regularAdress
	cmp RM, 0x06							;if mod = 00 print the regular mod (not when r/m = 110)
	jne .printRegularMod00
	jmp .printMod00
	;----------------------------------------------------------
	
	.regularAdress
	cmp D_W, 0x00
	jne .maibiD_W10
	readNext BYTE_NUM
	;+;+;+;
	cmp PREFIX, 0xFF
	je .noPrefix_0
	call putPrefix
	.noPrefix_0
	;+;+;+;
	writeln [fullAddress + di]
	;-----
	cmp BYTE_NUM, 0x01										;check if displacement byte is negative
	jne .notByteOp_0
	mov ah, 0
	cmp al, 0x7F
	jbe .notByteOp_0
	writeln minus
	neg al
	mov ah, 0
	call putHexStr
	jmp .noPlus_0
	.notByteOp_0
	;-----
	writeln plus
	call putHexStr
	.noPlus_0
	writeln rightSquareBracket
	writeln comma
	mov di, [savedWord]
	writeln [halfRegisters + di]
	jmp .end
	;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;
	.maibiD_W10
	cmp D_W, 0x02
	jne .maibiD_W01
	push di
	mov di, [savedWord]
	writeln [halfRegisters + di]
	writeln comma
	readNext BYTE_NUM
	;+;+;+;
	cmp PREFIX, 0xFF
	je .noPrefix_1
	call putPrefix
	.noPrefix_1
	;+;+;+;
	pop di
	writeln [fullAddress + di]
	;-----
	cmp BYTE_NUM, 0x01										;check if displacement byte is negative
	jne .notByteOp_1
	mov ah, 0
	cmp al, 0x7F
	jbe .notByteOp_1
	writeln minus
	neg al
	mov ah, 0
	call putHexStr
	writeln rightSquareBracket
	jmp .end
	.notByteOp_1
	;-----
	writeln plus
	call putHexStr
	writeln rightSquareBracket
	jmp .end
	;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;
	.maibiD_W01
	cmp D_W, 0x01
	jne .maibiD_W11
	readNext BYTE_NUM
	;+;+;+;
	cmp PREFIX, 0xFF
	je .noPrefix_2
	call putPrefix
	.noPrefix_2
	;+;+;+;
	writeln [fullAddress + di]
	;-----
	cmp BYTE_NUM, 0x01										;check if displacement byte is negative
	jne .notByteOp_2
	mov ah, 0
	cmp al, 0x7F
	jbe .notByteOp_2
	writeln minus
	neg al
	mov ah, 0
	call putHexStr
	jmp .noPlus_2
	.notByteOp_2 
	;-----
	writeln plus
	call putHexStr
	.noPlus_2
	writeln rightSquareBracket
	writeln comma
	mov di, [savedWord]
	writeln [fullRegisters + di]
	jmp .end
	;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;
	.maibiD_W11
	cmp D_W, 0x03
	jne .mod1001FIXED_REGrm
	push di
	mov di, [savedWord]
	writeln [fullRegisters + di]
	writeln comma
	readNext BYTE_NUM
	;+;+;+;
	cmp PREFIX, 0xFF
	je .noPrefix_3
	call putPrefix
	.noPrefix_3
	;+;+;+;
	pop di
	writeln [fullAddress + di]
	;-----
	cmp BYTE_NUM, 0x01										;check if displacement byte is negative
	jne .notByteOp_3
	mov ah, 0
	cmp al, 0x7F
	jbe .notByteOp_3
	writeln minus
	neg al
	mov ah, 0
	call putHexStr
	writeln rightSquareBracket
	jmp .end
	.notByteOp_3
	;-----
	writeln plus
	call putHexStr
	writeln rightSquareBracket
	jmp .end
	;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;-;
	.mod1001FIXED_REGrm
	readNext BYTE_NUM
	;+;+;+;
	cmp PREFIX, 0xFF
	je .noPrefix_4
	call putPrefix
	.noPrefix_4
	;+;+;+;
	writeln [fullAddress + di]
	;----
	cmp BYTE_NUM, 0x01										;check if displacement byte is negative
	jne .notByteOp_4
	mov ah, 0
	cmp al, 0x7F
	jbe .notByteOp_4
	writeln minus
	neg al
	mov ah, 0
	call putHexStr
	writeln rightSquareBracket
	jmp .end
	;----
	.notByteOp_4 
	writeln plus
	call putHexStr
	writeln rightSquareBracket
	jmp .end
	
	;**********************************************;
	.printMod11															;prints only the register names
	cmp D_W, 0x00
	jne .maybeD_W10
	writeln [halfRegisters + di]
	writeln comma
	mov di, [savedWord]
	writeln [halfRegisters + di]
	jmp .end
	;---
	.maybeD_W10
	cmp D_W, 0x02
	jne .maybeD_W01
	push di
	mov di, [savedWord]
	writeln [halfRegisters + di]
	writeln comma
	pop di
	writeln [halfRegisters + di]
	jmp .end
	;---
	.maybeD_W01
	cmp D_W, 0x01
	jne .maybeD_W11
	writeln [fullRegisters + di]
	writeln comma
	mov di, [savedWord]
	writeln [fullRegisters + di]
	jmp .end
	;---
	.maybeD_W11
	cmp D_W, 0x03
	jne .mod11FIXED_REGrm
	push di
	mov di, [savedWord]
	writeln [fullRegisters + di]
	writeln comma
	pop di
	writeln [fullRegisters + di]
	jmp .end
	;---
	.mod11FIXED_REGrm
	cmp W, 0x01
	je .maybeMod11Word
	writeln [halfRegisters + di]
	jmp .end
	.maybeMod11Word
	writeln [fullRegisters + di]
	jmp .end
	;******************************************;
	.printMod00:													;prints when mod = 00 only the displacement
	readNext 2
	cmp D_W, 0x00
	jne .maibeD_W10
	writeln leftSquareBracket
	call putHexStr
	writeln rightSquareBracket
	writeln comma
	mov di, [savedWord]
	writeln [halfRegisters + di]
	jmp .end
	;---
	.maibeD_W10
	cmp D_W, 0x02
	jne .maibeD_W01
	mov di, [savedWord]
	writeln [halfRegisters + di]
	writeln comma
	writeln leftSquareBracket
	call putHexStr
	writeln rightSquareBracket
	jmp .end
	;---
	.maibeD_W01
	cmp D_W, 0x01
	jne .maibeD_W11
	writeln leftSquareBracket
	call putHexStr
	writeln rightSquareBracket
	writeln comma
	mov di, [savedWord]
	writeln [fullRegisters + di]
	jmp .end
	;---
	.maibeD_W11
	cmp D_W, 0x03
	jne .mod00FIXED_REGrm
	mov di, [savedWord]
	writeln [fullRegisters + di]
	writeln comma
	writeln leftSquareBracket
	call putHexStr
	writeln rightSquareBracket
	jmp .end
	;---
	.mod00FIXED_REGrm
	writeln leftSquareBracket
	call putHexStr
	writeln rightSquareBracket
	jmp .end
	
	;*******************************************;
	.printRegularMod00:											;prints the regular mod = 00 (not when r/m = 110)
	cmp D_W, 0x00
	jne .maybeyD_W10
	;+;+;+;
	cmp PREFIX, 0xFF
	je .noPrefix_5
	call putPrefix
	.noPrefix_5
	;+;+;+;
	writeln [fullAddress + di]
	writeln rightSquareBracket
	writeln comma
	mov di, [savedWord]
	writeln [halfRegisters + di]
	jmp .end
	;---
	.maybeyD_W10
	cmp D_W, 0x02
	jne .maybeyD_W01
	push di
	mov di, [savedWord]
	writeln [halfRegisters + di]
	writeln comma
	;+;+;+;
	cmp PREFIX, 0xFF
	je .noPrefix_6
	call putPrefix
	.noPrefix_6
	;+;+;+;
	pop di
	writeln [fullAddress + di]
	writeln rightSquareBracket
	jmp .end
	;---
	.maybeyD_W01
	cmp D_W, 0x01
	jne .maybeyD_W11
	;+;+;+;
	cmp PREFIX, 0xFF
	je .noPrefix_7
	call putPrefix
	.noPrefix_7
	;+;+;+;
	writeln [fullAddress + di]
	writeln rightSquareBracket
	writeln comma
	mov di, [savedWord]
	writeln [fullRegisters + di]
	jmp .end
	;---
	.maybeyD_W11
	cmp D_W, 0x03
	jne .mod00FIXED_RERrm2
	push di
	mov di, [savedWord]
	writeln [fullRegisters + di]
	writeln comma
	;+;+;+;
	cmp PREFIX, 0xFF
	je .noPrefix_8
	call putPrefix
	.noPrefix_8
	;+;+;+;
	pop di
	writeln [fullAddress + di]
	writeln rightSquareBracket
	jmp .end
	;---
	.mod00FIXED_RERrm2
	;+;+;+;
	cmp PREFIX, 0xFF
	je .noPrefix_9
	call putPrefix
	.noPrefix_9
	;+;+;+;
	writeln [fullAddress + di]
	writeln rightSquareBracket
	jmp .end
	
	
	
	
	.end
	mov D_W, 0xFF
	mov W, 0xFF
	mov PREFIX, 0XFF
	pop cx
	pop ax
	pop di
		
ret
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;<<<<<<<<<<< 10. FORM ADDRESS W/ WORD BYTE PTR (LOGIC AND ARIT)>>>>>>>>>>>>>;
formInstrWB:
	; Form the rest of the instruction. If needed add 'word ptr' or 'byte ptr'.
	; AL - instruction byte
	push di
	push ax
	push cx
	
	cmp MD, 0x03					;check mod11
	je .Mod11
	cmp MD, 0x02					;check mod10
	je .Mod10
	cmp MD, 0x01					;check mod01
	je .Mod01
	
	.Mod00								;else mod 00
	cmp RM, 0x06
	jne .NotRm110					;if mod = 00 and r/m = 110
	mov BYTE_NUM, 0x02
	jmp .GetRegisterName
	.NotRm110							
	jmp .GetRegisterName
	
	.Mod11:
	mov BYTE_NUM, 0x01	
	jmp .GetRegisterName
	
	.Mod10:
	mov BYTE_NUM, 0x02
	jmp .GetRegisterName		
	
	.Mod01:
	mov BYTE_NUM, 0x01
	jmp .GetRegisterName
	
	.GetRegisterName:					; access the string in the string arrays holding the names of register								
	mov cl, 0x08
	mov al, RM
	mul cl
	mov di, ax
	
	cmp V_W, 0xFF							;for other cases
	jne .writeAddInstr
	mov al, W
	mov V_W, al
	mov W, 0xFF
	
	.writeAddInstr
	cmp MD, 0x03
	je .cont
	cmp V_W, 0x03
	je .V_Word
	cmp V_W, 0x01
	je .V_Word
	writeln strBPTR
	jmp .cont
	.V_Word
	writeln strWPTR
	
	.cont
	 cmp MD, 0x03							;if mod = 11 then just print register name
	 je .PrintMod11
	 cmp MD, 0									
	 jne .RegularAddress
	 cmp RM, 0x06							;if mod = 00 print the regular mod (not when r/m = 110)
	 jne .PrintRegularMod00
	 jmp .PrintMod00
	
	.RegularAddress
	readNext BYTE_NUM
	;+;+;+;
	cmp PREFIX, 0xFF					;check if Segment Override Prefix is needed
	je .noPrefix_10
	call putPrefix
	.noPrefix_10
	;+;+;+;
	writeln [fullAddress + di]
	;----
	cmp BYTE_NUM, 0x01			;check if displacement byte is negative
	jne .notByteOp_10
	mov ah, 0
	cmp al, 0x7F
	jbe .notByteOp_10
	writeln minus
	neg al
	mov ah, 0
	call putHexStr
	writeln rightSquareBracket
	jmp .end
	.notByteOp_10 
	;----
	writeln plus
	call putHexStr
	writeln rightSquareBracket
	jmp .end
	
	.PrintMod11
	cmp V_W, 0x00
	je .V_WByte_2
	cmp V_W, 0x02
	je .V_WByte_2
	writeln [fullRegisters + di]
	jmp .end
	.V_WByte_2
	writeln [halfRegisters + di]
	jmp .end
	
	.PrintMod00
	readNext 2
	writeln leftSquareBracket
	call putHexStr
	writeln rightSquareBracket
	jmp .end
	
	.PrintRegularMod00
	;+;+;+;
	cmp PREFIX, 0xFF
	je .noPrefix_11
	call putPrefix
	.noPrefix_11
	;+;+;+;
	writeln [fullAddress + di]
	writeln rightSquareBracket
	jmp .end
	
	
	.end
	cmp W, 0xFF
	je .finally
	writeln comma
	cmp V_W, 0x02
	jb .V_W1
	writeln regCL
	jmp .finally
	.V_W1
	writeln one
	
	.finally
	mov D_W, 0xFF
	mov V_W, 0xFF
	mov W, 0xFF
	mov PREFIX, 0XFF
	pop cx
	pop ax
	pop di
		
ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;<<<<<<<<<<< 11. PUT STR AND PREFIX >>>>>>>>>>>>>;
putHexStr:
	; Puts hex numbers to stdout
	; AX - brought data

	jmp .begin
	.localData:
	db '0000h$'
   
	.begin: 
	push dx 
	push ax
	push cx
	push bx
	push si
	push di
	mov bx, ax
	mov cx, 4
	mov si, 0
	mov di, 0
	.loop4:
	  mov dx, bx
	  and dh, 0xF0
	  times 4 shr dh, 1
	  mov dl, dh
	  cmp dl, '0'
	  add dl, '0'
	  cmp dl, '9'
	  jle .skip
		 sub  dl, '0'
		 add  dl, ('A'-10)
		 
	  .skip:
	  mov [.localData + si], dl
	  times 4 shl bx, 1
	  inc si
	  loop .loop4
	  
	 ; Get rid of trailing zeros
	 mov si, 0
	 mov cl, 3
	.checkZero
		mov dl, [.localData + si]
		cmp dl, '0'
		jne .end
		inc si
	loop .checkZero

	.end
	; Output the data
	mov dx, .localData
	add dx, si
	mov ah, 0x09
	int 0x21
	
	pop di
	pop si
	pop bx
	pop cx
	pop ax
	pop dx
ret 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;	  
putPrefix:
	;Put the segment override prefix before EA
	
	push ax
	push di
	push cx
	mov al, PREFIX
	mov cl, 0x08
	mul cl
	mov ah, 0
	mov di, ax
	writeln [segments + di]
	writeln colon
	pop cx
	pop di
	pop ax
	
ret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

section .data
	;Data
    
    strCMC:
		db '      CMC $'  
    strSTC:
		db '      STC $'  
    strCLC:
		db '      CLC $'  
    strRET:
		db '      RET $'  
    strRETF:
		db '      RETF $'
	strCLI:
		db '      CLI $'
	strCLD:
		db '      CLD $'
	strSTD:
		db '      STD $'
	strSTI:
		db '      STI $'
	strHLT:
		db '      HLT $'
	strWAIT:
		db '      WAIT $'
	strLOCK:
		db '      LOCK $'
	strINTO:
		db '      INTO $'
	strIRET:
		db '      IRET $'
	strINT_3h:
		db '      INT 3h $'
	strINT_4h:
		db '      INT 4h $'
	strINT:
		db '      INT $'
	strICBW:
		db '      CBW $'
	strICWD
		db '      CWD $'
	strDAA
		db '      DAA $'
	strAAA
		db '      AAA $'
	strIAAS:
		db '      AAS $'
	strIDAS:
		db '      DAS $'
	strXLAT:
		db '      XLATB $'
	strAAM
		db '      AAM $'
	strAAD
		db '      AAD $'
	strILAHF:
		db '      LAHF $'
	strISAHF:
		db '      SAHF $'
	strIPUSHF:
		db '      PUSHF $'
	strIPOPF:
		db '      POPF $'
	strJE:
		db '      JE $'
	strJL:
		db '      JL $'
    strJLE
		db '      JLE $'
	strJB
		db '      JB $'
	strJBE
		db '      JBE $'
	strJP
		db '      JP $'
	strJO
		db '      JO  $'
	strJS
		db '      JS  $'
	strJNE
		db '      JNE $'
	strJGE
		db '      JGE $'
	strJG
		db '      JG  $'
	strJAE
		db '      JAE $'
	strJA
		db '      JA  $'
	strJPO
		db '      JPO $'
	strJNO
		db '      JNO $'
	strJNS
		db '      JNS $'
	strLOOPNE
		db '      LOOPNE $'
	strLOOPE
		db '      LOOPE $'
	strLOOP
		db '      LOOP $'
	strJCXZ
		db '      JCXZ $'
	strJMP
		db '      JMP $'
	strCALL
		db '      CALL $'
	strREPE
		db '      REPE $'
	strREPNE
		db '      REPNE $'
	strMOVSB
		db '      MOVSB $'
	strMOVSW
		db '      MOVSW $'
	strCMPSB
		db '      CMPSB $'
	strCMPSW
		db '      CMPSW $'
	strSCASB
		db '      SCASB $'
	strSCASW
		db '      SCASW $'
	strLODSB
		db '      LODSB $'
	strLODSW
		db '      LODSW $'
	strSTOSB
		db '      STOSB $'
	strSTOSW
		db '      STOSW $'
	strXOR
		db '      XOR $'
	strOR
		db '      OR $'
	strTEST
		db '      TEST $'
	strAND
		db '      AND $'
	strSHL
		db '      SHL $'
	strSHR
		db '      SHR $'
	strSAR
		db '      SAR $'
	strROL
		db '      ROL $'
	strROR
		db '      ROR $'
	strRCL
		db '      RCL $'
	strRCR
		db '      RCR $'	
	strNOT
		db '      NOT $'
	strIDIV
		db '      IDIV $'
	strDIV
		db '      DIV $'
	strIMUL
		db '      IMUL $'
	strMUL
		db '      MUL $'
	strCMP
		db '      CMP $'
	strSBB
		db '      SBB $'
	strSUB
		db '      SUB $'
	strADC
		db '      ADC $'
	strADD
		db '      ADD $'
	strDEC
		db '      DEC $'
	strINC
		db '      INC $'
	strNEG
		db '      NEG $'
	strLEA
		db '      LEA $'
	strLDS
		db '      LDS $'
	strLES
		db '      LES $'
	strIN
		db '      IN $'
	strOUT
		db '      OUT $'
	strNOP
		db '      NOP $'
	strXCHG
		db '      XCHG $'
	strPOP
		db '      POP $'
	strPUSH
		db '      PUSH $'
	strMOV
		db '      MOV $'
	strFLD
		db '      FLD $'
		
	;<<<<<<<<<<< 12. DATA MID>>>>>>>>>>>>>;
		
	one:
		db '1$'
	emptyString:
		db '$'
	colon:
		db ':$'
	plus:
		db '+$'
	minus:
		db '-$'
	leftSquareBracket:
		db '[$'
	rightSquareBracket:
		db ']$'
	leftRoundBracket:
		db '($'
	rightRoundBracket:
		db ')$'
	comma:
		db ',$'
	regAX:
		db 'AX$'
	regBX:
		db 'BX$'
	regCX:
		db 'CX$'
	regDX:
		db 'DX$'
	regSP:
		db 'SP$'
	regBP:
		db 'BP$'
	regSI:
		db 'SI$'
	regDI:
		db 'DI$'
	regAL:
		db 'AL$'
	regBL:
		db 'BL$'
	regCL:
		db 'CL$'
	regDL:
		db 'DL$'
	regAH:
		db 'AH$'
	regBH:
		db 'BH$'
	regCH:
		db 'CH$'
	regDH:
		db 'DH$'
	comboBX_SI:
		db '[BX+SI$'
	comboBX_DI:
		db '[BX+DI$'
	comboBP_SI:
		db '[BP+SI$'
	comboBP_DI:
		db '[BP+DI$'
	comboSI:
		db '[SI$'
	comboDI:
		db '[DI$'
	comboBP:
		db '[BP$'
	comboBX:
		db '[BX$'
	segES:
		db 'ES$'
	segCS:
		db 'CS$'
	segSS:
		db 'SS$'
	segDS:
		db 'DS$'
	
	
	logicCommands:
		dq strROL, strROR, strRCL, strRCR, strSHL,  strSHR, emptyString, strSAR
	fullRegisters:	
		dq regAX, regCX, regDX, regBX, regSP, regBP, regSI, regDI
	halfRegisters:
		dq regAL, regCL, regDL, regBL, regAH, regCH, regDH, regBH
	fullAddress:
		dq comboBX_SI, comboBX_DI, comboBP_SI, comboBP_DI, comboSI, comboDI, comboBP, comboBX
    segments:
		dq segES, segCS, segSS, segDS
	
	strWPTR:
		db 'WORD PTR $'
	strBPTR:
		db 'BYTE PTR $'
	strFAR
		db 'FAR $'
    strDB:
		db '      DB   ' 
    takenArgument:
		db 00, 00, 'h$'
	
	errorOpeningFile:
		db 'Error opening file $'
	errorReadingFile:
		db 'Error reading file $'
    errorReadingArgument:
		db 'Error reading argument $'

    naujaEilute:   
		db 0x0D, 0x0A, '$'  ; NL and CR
    comLineLength:
		db 00
    comLineArgument:
		times 255 db 00
		
    currentFile:
		dw 0FFFh
	savedWord:
		dw 00
	lseek:
		dw 0x100					; Origin
		
	;<<<<<<<<<<< 13. END>>>>>>>>>>>>>;