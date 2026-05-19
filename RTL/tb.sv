`timescale 1ns / 1ps

module tb_riscv_pipe_cpu();

    // Segnali di test
    logic clk;
    logic reset;
    logic [31:0] instr_obs;
    logic [31:0] pc_obs;

    // Variabili di conteggio e tempo
    integer i;
    int cycle_count = 0;
    
    // Per calcolare il tempo di esecuzione con precisione (Real)
    real exec_time_ns; 
    real exec_time_us;

    // Parametri per il Clock a 170 MHz
    // T = 1 / 170 MHz = 5.882 ns (Periodo totale)
    // Semi-periodo = 5.882 / 2 = 2.941 ns
    localparam real CLK_PERIOD_NS = 5.882; 
    localparam real HALF_CLK_PERIOD_NS = 2.941;

    // Istanza della CPU PIPELINED
    riscv_pipe_cpu dut (
        .clk(clk),
        .reset(reset),
        .instr_obs(instr_obs),
        .pc_obs(pc_obs)
    ); 

    // Generazione del clock a 170 MHz
    initial begin
        clk = 0;
        forever #(HALF_CLK_PERIOD_NS) clk = ~clk;
    end

    // Contatore dei cicli
    always @(posedge clk) begin
        if (!reset) begin
            cycle_count++;
        end
    end

    // Monitor a schermo
    initial begin
        $monitor("Tempo: %0t ns | Ciclo: %0d | PC: %0d (0x%0h) | Instr: 0x%08h", 
                 $time, cycle_count, pc_obs, pc_obs, instr_obs);
    end

    // Blocco Principale
    initial begin
        $display("==================================================");
        $display(" INIZIO SIMULAZIONE CPU RISC-V (PIPELINED BTB)    ");
        $display(" Target Freq: 170 MHz (Periodo: %f ns)", CLK_PERIOD_NS);
        $display("==================================================");
        
        reset = 1;
        #50;  
        
        reset = 0; 
        $display("--> Reset rilasciato. Inizio esecuzione istruzioni...");
        $display("--> In attesa della scrittura sul registro x31...");
        
        // CONDIZIONE DI STOP INTELLIGENTE
        // Aspettiamo che il Program Counter arrivi all'istruzione di Halt (PC = 48)
        wait(pc_obs == 48);
        
        // A questo punto, l'istruzione "addi x31" (PC = 44) è appena stata fetchata.
        // Diamo alla pipeline esattamente 4 cicli di clock per farla arrivare
        // allo stadio di Writeback (WB) e scrivere nel registro!
        #(CLK_PERIOD_NS * 4);

        // Calcolo del tempo di esecuzione effettivo simulato
        exec_time_ns = cycle_count * CLK_PERIOD_NS;
        exec_time_us = exec_time_ns / 1000.0;

        $display("==================================================");
        $display(" SIMULAZIONE COMPLETATA CON SUCCESSO!             ");
        $display("==================================================");
        
        // Stampiamo i risultati finali per verifica
        $display("PC al momento dello stop  : %0d", pc_obs);
        $display("--------------------------------------------------");
        $display(" STATISTICHE DI ESECUZIONE (PIPELINE)             ");
        $display(" Frequenza di Clock        : 170 MHz");
        $display(" Cicli Totali Effettivi    : %0d", cycle_count);
        $display(" Tempo di Esecuzione       : %f ns", exec_time_ns);
        $display(" Tempo di Esecuzione       : %f us", exec_time_us);
        $display("==================================================");
        
        $finish;
    end

endmodule
