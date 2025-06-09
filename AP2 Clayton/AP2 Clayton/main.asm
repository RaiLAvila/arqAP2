;***************************************************************************
;* PROJETO ASSEMBLY ATMEGA2560 - PROCESSAMENTO DE FRASE E TABELAS         *
;* *
;* Integrantes:                                                            *
;* Raí Lamper de Avila - 202402627279 - TA                                 *
;* Gabriel Maia Sampaio - 202402627295 - TA                                *
;* André Luiz Mendes do Nascimento Ribeiro - 202401020631 - TA             *
;* Vinícius Marinho Queiroz - 202407321976 - TA                             *
;* Victor Alvarenga Hwang - 202208766005 - TA                              *
;* *
;* Objetivo Geral do Programa:                                             *
;* 1. Ler uma frase pré-definida (exemplo: "Raizao 4321").                 *
;* 2. Comparar cada caractere da frase com uma lista especial de 15        *
;* caracteres também pré-definida.                                         *
;* 3. Criar uma nova tabela que resume as informações sobre cada           *
;* caractere único encontrado na frase: qual é o caractere, quantas        *
;* vezes ele apareceu, e se ele pertencia ou não à lista especial.         *
;***************************************************************************

.NOLIST
.INCLUDE "m2560def.inc"
.LIST

;***************************************************************************
;* Definições de Constantes                                                *
;* Define endereços de memória e tamanhos de dados para o programa.        *
;***************************************************************************

.EQU TABELA_ASCII_ADDR    = 0x0200
.EQU FRASE_ADDR           = 0x0300
.EQU TABELA_SAIDA_ADDR    = 0x0400

.EQU TAMANHO_TABELA_ASCII  = 15
.EQU TAMANHO_MAX_FRASE     = 30
.EQU TAMANHO_FRASE_LITERAL_COM_NULL = 12
.EQU TAMANHO_ENTRADA_SAIDA  = 3
.EQU END_OF_STRING         = 0x00

;*********************************************************************************
;* Definição de Registradores                                                    *
;* Atribui nomes simbólicos aos registradores para clareza no código.          *
;*********************************************************************************

.DEF temp_reg             = R16
.DEF char_lido            = R17
.DEF contador_ocorrencias = R18
.DEF flag_pertence_tabela = R19
.DEF char_tabela_ascii    = R20
.DEF char_frase_temp      = R21
.DEF contador_copia_flash = R24
.DEF temp_reg2            = R23
.DEF temp_reg3            = R25

.DEF ptr_saida_offset     = R22

; --- Macros para salvar/restaurar registradores na pilha ---
; Usadas para preservar o estado dos registradores antes e depois das sub-rotinas.

.MACRO mSaveRegs5
    PUSH @0
    PUSH @1
    PUSH @2
    PUSH @3
    PUSH @4
.ENDM

.MACRO mRestoreRegs5
    POP @4
    POP @3
    POP @2
    POP @1
    POP @0
.ENDM

.MACRO mSaveRegs7
    PUSH @0
    PUSH @1
    PUSH @2
    PUSH @3
    PUSH @4
    PUSH @5
    PUSH @6
.ENDM

.MACRO mRestoreRegs7
    POP @6
    POP @5
    POP @4
    POP @3
    POP @2
    POP @1
    POP @0
.ENDM

;***************************************************************************
;* Segmento de Dados (.DSEG) - Alocação de espaço na SRAM                  *
;* Reserva blocos de memória RAM para tabelas e frases.                    *
;***************************************************************************

.DSEG
.ORG TABELA_ASCII_ADDR
TABELA_ASCII_15_CARACTERES:
    .BYTE TAMANHO_TABELA_ASCII

.ORG FRASE_ADDR
FRASE_USUARIO:
    .BYTE TAMANHO_MAX_FRASE

.ORG TABELA_SAIDA_ADDR
TABELA_SAIDA_DADOS:
    .BYTE (TAMANHO_MAX_FRASE * TAMANHO_ENTRADA_SAIDA)

;***************************************************************************
;* Segmento de Código (.CSEG)                                              *
;* Contém as instruções do programa e dados fixos.                         *
;***************************************************************************
.CSEG
.ORG 0x0000
    RJMP RESET_HANDLER

.ORG 0x0100

TABELA_ASCII_FLASH:
    .DB 'A', 'c', 'G', '2', 'd', 'M', 'R', 'Z', 'x', 'm', 'b', '5', 'H', 'u', '7'

FRASE_USUARIO_FLASH:
    .DB "Raizao 4321", END_OF_STRING

RESET_HANDLER:
    ; Inicialização do Stack Pointer
    LDI temp_reg, HIGH(RAMEND)
    OUT SPH, temp_reg
    LDI temp_reg, LOW(RAMEND)
    OUT SPL, temp_reg

    ; Copiando tabela de referência ASCII da Flash para SRAM
    LDI ZL, LOW(TABELA_ASCII_FLASH*2)
    LDI ZH, HIGH(TABELA_ASCII_FLASH*2)

    LDI XL, LOW(TABELA_ASCII_ADDR)
    LDI XH, HIGH(TABELA_ASCII_ADDR)

    LDI contador_copia_flash, TAMANHO_TABELA_ASCII

COPIA_ASCII_LOOP:
    CPI contador_copia_flash, 0
    BREQ FIM_COPIA_ASCII
    LPM temp_reg2, Z+
    ST X+, temp_reg2
    DEC contador_copia_flash
    RJMP COPIA_ASCII_LOOP
FIM_COPIA_ASCII:

    ; Copiando a frase de teste da Flash para SRAM
    LDI ZL, LOW(FRASE_USUARIO_FLASH*2)
    LDI ZH, HIGH(FRASE_USUARIO_FLASH*2)
    LDI XL, LOW(FRASE_ADDR)
    LDI XH, HIGH(FRASE_ADDR)
    LDI contador_copia_flash, TAMANHO_FRASE_LITERAL_COM_NULL
COPIA_FRASE_LOOP:
    CPI contador_copia_flash, 0
    BREQ FIM_COPIA_FRASE
    LPM temp_reg2, Z+
    ST X+, temp_reg2
    DEC contador_copia_flash
    RJMP COPIA_FRASE_LOOP
FIM_COPIA_FRASE:

    ; Inicializa o offset da tabela de saída
    CLR ptr_saida_offset

    ; Chama a rotina principal para processar a frase
    RCALL PROCESSA_FRASE

END_PROGRAM:
    ; Ponto final de execução, mantém o processador em loop infinito.
    RJMP END_PROGRAM

;***************************************************************************
;* Sub-rotina: PROCESSA_FRASE                                              *
;* Objetivo: Lê a frase, caractere por caractere, e processa cada um,      *
;* verificando-o, contando ocorrências e atualizando a tabela de saída.    *
;***************************************************************************

PROCESSA_FRASE:
    LDI ZL, LOW(FRASE_ADDR)
    LDI ZH, HIGH(FRASE_ADDR)

PROXIMO_CARACTERE_FRASE:
    LD char_lido, Z+
    CPI char_lido, END_OF_STRING
    BREQ FIM_PROCESSA_FRASE

    RCALL VERIFICA_NA_TABELA_INICIAL
    RCALL CONTA_OCORRENCIAS
    RCALL ATUALIZA_TABELA_SAIDA

    RJMP PROXIMO_CARACTERE_FRASE

FIM_PROCESSA_FRASE:
    RET

;***************************************************************************
;* Sub-rotina: VERIFICA_NA_TABELA_INICIAL                                  *
;* Objetivo: Compara o caractere lido da frase com a tabela de referência  *
;* para determinar se ele pertence a ela.                                  *
;***************************************************************************

VERIFICA_NA_TABELA_INICIAL:
    mSaveRegs5 temp_reg, char_tabela_ascii, temp_reg2, YL, YH

    CLR flag_pertence_tabela

    LDI temp_reg, LOW(TABELA_ASCII_ADDR)
    MOV YL, temp_reg
    LDI temp_reg, HIGH(TABELA_ASCII_ADDR)
    MOV YH, temp_reg

    LDI temp_reg2, TAMANHO_TABELA_ASCII

VT_LOOP_CMP:
    LD char_tabela_ascii, Y+
    CP char_lido, char_tabela_ascii
    BRNE VT_CONTINUA_LOOP

    LDI flag_pertence_tabela, 1
    RJMP VT_FIM_VERIFICACAO

VT_CONTINUA_LOOP:
    DEC temp_reg2
    BRNE VT_LOOP_CMP

VT_FIM_VERIFICACAO:
    mRestoreRegs5 temp_reg, char_tabela_ascii, temp_reg2, YL, YH
    RET

;***************************************************************************
;* Sub-rotina: CONTA_OCORRENCIAS                                           *
;* Objetivo: Percorre a frase completa para contar quantas vezes o         *
;* caractere atual aparece.                                                *
;***************************************************************************
CONTA_OCORRENCIAS:
    PUSH ZH
    PUSH ZL

    CLR contador_ocorrencias

    LDI ZL, LOW(FRASE_ADDR)
    LDI ZH, HIGH(FRASE_ADDR)

LOOP_CONTA:
    LD char_frase_temp, Z+
    CPI char_frase_temp, END_OF_STRING
    BREQ FIM_CONTA

    CP char_frase_temp, char_lido
    BRNE LOOP_CONTA

    INC contador_ocorrencias
    RJMP LOOP_CONTA

FIM_CONTA:
    POP ZL
    POP ZH
    RET

;***************************************************************************
;* Sub-rotina: ATUALIZA_TABELA_SAIDA                                       *
;* Objetivo: Adiciona uma nova entrada para um caractere na tabela de      *
;* saída ou atualiza sua contagem se já estiver presente.                  *
;***************************************************************************
ATUALIZA_TABELA_SAIDA:
    mSaveRegs7 temp_reg, temp_reg2, temp_reg3, R0, char_frase_temp, XL, XH

    ; Procura se o caractere já existe na tabela de saída
    LDI XL, LOW(TABELA_SAIDA_ADDR)
    LDI XH, HIGH(TABELA_SAIDA_ADDR)

    MOV temp_reg2, ptr_saida_offset
    TST temp_reg2
    BREQ ATS_ADICIONA_NOVA_ENTRADA

ATS_LOOP_BUSCA:
    LD char_frase_temp, X
    CP char_lido, char_frase_temp
    BRNE ATS_PROXIMA_ENTRADA_BUSCA

    ; Caractere encontrado, incrementa a contagem
    ADIW X, 1
    LD R0, X
    INC R0
    ST X, R0
    RJMP ATS_FIM_ATUALIZACAO

ATS_PROXIMA_ENTRADA_BUSCA:
    ADIW X, TAMANHO_ENTRADA_SAIDA
    DEC temp_reg2
    BRNE ATS_LOOP_BUSCA

ATS_ADICIONA_NOVA_ENTRADA:
    ; Calcula o endereço para adicionar a nova entrada
    MOV temp_reg, ptr_saida_offset
    CLR temp_reg2

    CPI temp_reg, 0
    BREQ ATS_SKIP_MULT_OFFSET

ATS_CALC_OFFSET_NON_ZERO:
    MOV R0, temp_reg
    LSL R0
    ADD R0, temp_reg
    RJMP ATS_APLICA_OFFSET

ATS_SKIP_MULT_OFFSET:
    CLR R0

ATS_APLICA_OFFSET:
    LDI XL, LOW(TABELA_SAIDA_ADDR)
    LDI XH, HIGH(TABELA_SAIDA_ADDR)

    ADD XL, R0
    ADC XH, temp_reg2

    ; Escreve os dados da nova entrada: caractere, contagem e flag
    ST X+, char_lido
    ST X+, contador_ocorrencias
    ST X, flag_pertence_tabela

    ; Incrementa o contador de entradas na tabela de saída
    INC ptr_saida_offset

ATS_FIM_ATUALIZACAO:
    mRestoreRegs7 temp_reg, temp_reg2, temp_reg3, R0, char_frase_temp, XL, XH
    RET

;---------------------------------------------------------------
; Fluxograma
; Início 
;   --> Copia TABELA_ASCII da Flash para SRAM
;   --> Copia FRASE_USUARIO da Flash para SRAM
;   --> ptr_saida_offset ? 0
;   --> PROCESSA_FRASE:
;       --> Ler caractere da frase
;       --> É nulo (END_OF_STRING)?
;           --> Sim  --> Fim do processamento (RET)
;           --> Não  --> Verifica se pertence à tabela
;                     --> Conta ocorrências na frase
;                     --> Caractere já está na saída?
;                         --> Sim  --> Atualiza contagem
;                         --> Não  --> Escreve (char, contagem, pertence) na saída
;       --> Próximo caractere --> (loop)
;   --> Fim
;---------------------------------------------------------------
