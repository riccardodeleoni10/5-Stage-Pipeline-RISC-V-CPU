RISC-V 5-Stage Pipelined Core with 2-Bit Bimodal BTB

Benvenuto nel repository di **riscv_pipe_cpu**, un core di processore RISC-V a 5 stadi interamente sviluppato in VHDL. L'architettura implementa tecniche avanzate di esecuzione speculativa tramite un predittore di salto bimodale a 2 bit (*Branch Target Buffer*), ottimizzando significativamente l'efficienza di esecuzione ed eliminando i colli di bottiglia strutturali.


<p align="center">
  <img width="1827" height="843" alt="Schema dell'Architettura della CPU" src="https://github.com/user-attachments/assets/e48eaecd-233d-4e10-ae33-a6e2d8db5530" />
</p>

---

## 🚀 Caratteristiche Principali

* **Pipeline Classica a 5 Stadi:** Separazione netta delle fasi di *Fetch (IF)*, *Decode (ID)*, *Execute (EX)*, *Memory (MEM)* e *Writeback (WB)* per massimizzare il parallelismo a livello di istruzione.
* **Predittore di Salto Bimodale a 2 Bit (BTB):** Tabella RAM distribuita da 64 righe con automa a stati finiti a 4 stati (`MP`, `WMP`, `WPT`, `PT`). Riduce drasticamente le penalità di cambio flusso (*pipeline bubbles*) ereditate dai cicli iterativi.
* **Logica di Forwarding Totale (Bypass Network):** Unità di bypass combinatoria operante tra gli stadi EX/MEM e MEM/WB verso gli ingressi dell'ALU. Risolve i rischi sui dati (*Data Hazards*) senza inserire stalli intermedi.
* **Timing e Sintesi FPGA:** Frequenza massima teorica verificata a **171 MHz** su hardware target, con un abbondante margine di sicurezza operativo impostato a **170 MHz** (Slack positivo di ben `4.178 ns` rispetto ai vincoli standard).

---

## 🗺️ Panoramica dell'Architettura

La CPU esegue un subset ottimizzato dell'ISA RISC-V, supportando istruzioni fondamentali di calcolo, memoria e salto:
* **Memory Access:** `lw` (Load Word), `sw` (Store Word).
* **Calcolo ALU:** `add`, `sub`, `and`, `or`, `addi`.
* **Flusso di Controllo:** `beq` (Branch if Equal), `bge` (Branch if Greater or Equal), `jal` (Jump and Link).

### Il Motore di Predizione a 2 Bit

Il BTB organizza la memoria interna memorizzando il `tag` (PC completo a 32 bit), il `target` (indirizzo di atterraggio del salto) e lo `state` codificato tramite il tipo enumerato `btb_state_t`. 

L'automa a stati gestisce le transizioni dinamicamente nello stadio Execute:
### Il Motore di Predizione a 2 Bit (Bimodal Predictor)

Il Branch Target Buffer (BTB) organizza la sua memoria interna memorizzando il `tag` (PC completo a 32 bit per evitare aliasing), il `target` (indirizzo di destinazione calcolato) e lo `state` (codificato tramite il tipo enumerato `btb_state_t`). 

L'automa a stati finiti gestisce le transizioni dinamicamente all'interno dello stadio Execute, basandosi sulla cronologia dei salti. Di seguito la Macchina a Stati implementata:

```text
         Salto Preso (1)                  Salto Preso (1)
        ┌───────────────┐                ┌───────────────┐
        │               │                │               │
  ┌─────┴─────┐   ┌─────▼─────┐    ┌─────┴─────┐   ┌─────▼─────┐
  │    MP     ├───►    WMP    ├───►│    WPT    ├───►     PT    │
  │ Fortem.   │   │ Debolm.   │    │ Debolm.   │   │ Fortem.   │
  │ Non Preso │◄──┤ Non Preso │ ◄──┤ Preso     │◄──┤ Preso     │
  └─────▲─────┘   └─────┬─────┘    └─────▲─────┘   └─────┬─────┘
        │               │                │               │
        └───────────────┘                └───────────────┘
      Salto Non Preso (0)              Salto Non Preso (0)

```
* **IF Stage (Predizione Combinatoria):** Il PC corrente interroga istantaneamente il BTB tramite i bit `[7:2]`. Se il Tag coincide con il PC e lo stato è debolmente/fortemente preso (`WPT` o `PT`), il PC successivo viene dirottato verso il target in un solo ciclo di clock.
* **EX Stage (Logica di Correzione e Update):** Se l'esito reale calcolato dal comparatore differisce dalla scommessa effettuata dal Fetch, il segnale `btb_ex_error` si alza immediatame, innescando un **Flush d'emergenza** degli stadi IF/ID e ID/EX, riportando il PC sulla retta via (`ex_pc_branch` se preso, `ex_pc_fallback` se non preso).

---

## 📊 Analisi delle Performance (IPC Benchmark)

I test di simulazione eseguiti sul calcolo della serie di Fibonacci evidenziano l'impatto straordinario del BTB sull'efficienza computazionale globale:

| Metrica Hardware | CPU Classica (No BTB) | CPU con Bimodal BTB (2-bit) |
| :--- | :---: | :---: |
| **Cicli di Clock ($N=10$)** | ~95 cicli | **77 cicli** |
| **Istruzioni Utili Chiuse** | 67 | 67 |
| **Penalità di Flush perse** | 22 cicli | **4 cicli** |
| **IPC Reale (*Instructions Per Cycle*)** | **0.71** | **0.87** |
| **Guadagno di Efficienza** | Baseline | **+ 22.5%** |
---

## 🛠️ Struttura dei File del Progetto

```ascii
├── riscv_pipe_cpu.vhd   # Codice sorgente VHDL completo del Processore
└── tb_riscv_pipe_cpu.sv # Testbench avanzato in SystemVerilog tarato a 170 MHz
