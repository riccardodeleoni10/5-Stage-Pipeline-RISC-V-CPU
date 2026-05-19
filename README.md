readme_text = """# RISC-V 5-Stage Pipelined CPU with 2-bit Bimodal BTB

Benvenuto nel repository di **riscv_pipe_cpu**, un core di processore RISC-V a 5 stadi interamente sviluppato in VHDL. L'architettura implementa tecniche avanzate di esecuzione speculativa tramite un predittore di salto bimodale a 2 bit (*Branch Target Buffer*).

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
