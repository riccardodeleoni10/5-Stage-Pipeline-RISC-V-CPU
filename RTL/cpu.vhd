library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL; 

entity riscv_pipe_cpu is
generic (
    INSTR_MEM_DEPTH : integer := 1024;
    DATA_MEM_DEPTH  : integer := 1024
);
Port ( 
    clk             : in std_logic;
    reset           : in std_logic;
    instr_obs       : out std_logic_vector(31 downto 0);
    pc_obs          : out std_logic_vector(31 downto 0)
);
end riscv_pipe_cpu;

architecture Behavioral of riscv_pipe_cpu is
--------------------------------------------------------------------------------
-- Elementi di memoria e Segnali globali
--------------------------------------------------------------------------------
type reg_file_t is array(0 to 31) of std_logic_vector(31 downto 0);
type instr_mem_t is array (0 to INSTR_MEM_DEPTH-1) of std_logic_vector(31 downto 0);
type data_mem_t is array (0 to DATA_MEM_DEPTH-1)  of std_logic_vector(31 downto 0);
signal instr_mem : instr_mem_t := (
    0  => x"00002083",   -- lw  x1,  0(x0)        ; x1 <- F(0) = 0
    1  => x"00402103",   -- lw  x2,  4(x0)        ; x2 <- F(1) = 1
    2  => x"00802183",   -- lw  x3,  8(x0)        ; x3 <- N
    3  => x"00C02203",   -- lw  x4, 12(x0)        ; x4 <- 1
    4  => x"00018C63",   -- beq x3, x0, done      ; se counter==0 -> done
    5  => x"002082B3",   -- add x5, x1, x2        ; x5 = x1 + x2
    6  => x"000160B3",   -- or  x1, x2, x0        ; x1 = x2
    7  => x"0002E133",   -- or  x2, x5, x0        ; x2 = x5
    8  => x"404181B3",   -- sub x3, x3, x4        ; x3 -= 1
    9  => x"FE0006E3",   -- beq x0, x0, loop      ; jump back
    10 => x"00102823",   -- sw  x1, 16(x0)        ; M[16] <- F(N)
    11 => x"00500f93",   -- addi x31 x0 5         ; x31 = x0 + x5
    12 => x"00000063",   -- beq x0, x0, halt      ; halt infinito
    others => x"00000000"
);
signal data_mem : data_mem_t := (
    0      => x"00000000",   -- F(0)        = 0errors
    1      => x"00000001",   -- F(1)        = 1
    2      => x"0000000A",   -- N           = 14
    3      => x"00000001",   -- decremento  = 1
    others => x"00000000"    -- slot 4 riceve il risultato F(N)
);



signal reg_file : reg_file_t := (others => (others => '0'));
signal PC_s             : std_logic_vector(31 downto 0) := (others => '0');
signal PC_next_s        : std_logic_vector(31 downto 0); 
signal PC_p4_s          : std_logic_vector(31 downto 0); 

signal read_data1_s     : std_logic_vector(31 downto 0);
signal read_data2_s     : std_logic_vector(31 downto 0);
signal WB_data_s        : std_logic_vector(31 downto 0); 

signal instruction      : std_logic_vector(31 downto 0);


----------------------------------------------------------------------------
-- OPC_codes & Funct
----------------------------------------------------------------------------
constant OP_IRRI     : std_logic_vector(6 downto 0) := "0110011";
constant OP_STORE    : std_logic_vector(6 downto 0) := "0100011";
constant OP_LOAD     : std_logic_vector(6 downto 0) := "0000011"; 
constant OP_BRANCH   : std_logic_vector(6 downto 0) := "1100011";
constant OP_IMM      : std_logic_vector(6 downto 0) := "0010011";

constant F3_ADD      : std_logic_vector(2 downto 0) := "000";
constant F3_SUB      : std_logic_vector(2 downto 0) := "000";
constant F3_AND      : std_logic_vector(2 downto 0) := "111";
constant F3_OR       : std_logic_vector(2 downto 0) := "110";
constant F7_b5_SUB   : std_logic :='1';

--------------------------------------------------------------------------------
-- REGISTRI PIPELINE
--------------------------------------------------------------------------------

-- Registro IF/ID
type if_id_reg_t is record 
        pc    : std_logic_vector(31 downto 0);
        instr : std_logic_vector(31 downto 0);
        btb_predict_bit: std_logic;
end record;

constant IF_ID_RESET : if_id_reg_t := (
        pc    => (others => '0'),
        instr => x"00000000",
        btb_predict_bit => '0'
);

signal if_id_reg_d, if_id_reg_q : if_id_reg_t;

-- Registro ID/EX
type id_ex_reg_t is record
        instr       : std_logic_vector(31 downto 0);
        pc          : std_logic_vector(31 downto 0);
        btb_predict_bit: std_logic;
        read_data_1 : std_logic_vector(31 downto 0);
        read_data_2 : std_logic_vector(31 downto 0);
        imm         : std_logic_vector(31 downto 0);
        funct3      : std_logic_vector(2 downto 0);
        rd          : std_logic_vector(4 downto 0);
        funct7_b5   : std_logic;
        mem_to_reg  : std_logic;
        reg_write   : std_logic;
        mem_read    : std_logic;
        mem_write   : std_logic;
        branch      : std_logic;
        alu_op      : std_logic_vector(1 downto 0);
        alu_src     : std_logic;
end record;

constant ID_EX_RESET : id_ex_reg_t := (
        instr       => (others => '0'),
        pc          => (others => '0'),
        btb_predict_bit => '0',
        read_data_1 => (others => '0'),
        read_data_2 => (others => '0'),
        imm         => (others => '0'),
        funct3      => (others => '0'),
        rd          => (others => '0'),
        funct7_b5   => '0',
        mem_to_reg  => '0',
        reg_write   => '0',
        mem_read    => '0',
        mem_write   => '0',
        branch      => '0',
        alu_op      => (others => '0'),
        alu_src     => '0'
);

signal id_ex_reg_d, id_ex_reg_q : id_ex_reg_t;

-- Registro EX/MEM
type ex_mem_reg_t is record
    instr       : std_logic_vector(31 downto 0);
    alu_result  : std_logic_vector(31 downto 0);
    --pc_branch   : std_logic_vector(31 downto 0);
    --zero        : std_logic;
    rd          : std_logic_vector(4 downto 0); 
    read_data_2 : std_logic_vector(31 downto 0); 
    mem_to_reg  : std_logic;
    reg_write   : std_logic;
    mem_read    : std_logic;
    mem_write   : std_logic;
   -- branch      : std_logic;
end record;

constant EX_MEM_RESET : ex_mem_reg_t := (
    instr       => (others => '0'),
    alu_result  => (others => '0'),
    rd          => (others => '0'),
    read_data_2 => (others => '0'),
    mem_to_reg  => '0',
    reg_write   => '0',
    mem_read    => '0',
    mem_write   => '0'
);

signal ex_mem_reg_d, ex_mem_reg_q : ex_mem_reg_t;

-- Registro MEM/WB
type mem_wb_reg_t is record
    mem_to_reg    : std_logic;
    reg_write     : std_logic;
    alu_result    : std_logic_vector(31 downto 0);
    data_mem_data : std_logic_vector(31 downto 0);
    rd            : std_logic_vector(4 downto 0); 
end record; 

constant MEM_WB_RESET : mem_wb_reg_t := (
    mem_to_reg    => '0',
    reg_write     => '0',
    alu_result    => (others => '0'),
    data_mem_data => (others => '0'),
    rd            => (others => '0')
);
signal mem_wb_reg_d, mem_wb_reg_q : mem_wb_reg_t;

--------------------------------------------------------------------------------
-- 1-BIT BRANCH PREDICTION LOGIC
--------------------------------------------------------------------------------
type btb_state_t is (MP,WMP,WPT,PT);     -- misspreditction,weak-missprediction, weak prediction taken, prediction taken
type btb_reg_t is record
        tag   : std_logic_vector(31 downto 0);
        target: std_logic_vector(31 downto 0);
        state : btb_state_t;
end record; 

type btb_ram_t is array (0 to 63) of btb_reg_t;
signal btb : btb_ram_t := (others => ( (others=>'0'), (others=>'0'),WPT));
signal btb_next_state : btb_state_t;
-- Segnali IF (Fetch)
signal btb_if_index         : std_logic_vector(5 downto 0); 
signal btb_if_predict_taken : std_logic;

-- Segnali EX (Execute)
signal btb_ex_actual_taken   : std_logic;
signal btb_ex_pc_fallback    : std_logic_vector(31 downto 0);
signal btb_ex_update_index   : std_logic_vector(5 downto 0);
signal btb_ex_error         : std_logic;
signal btb_ex_pc_correction  : std_logic_vector(31 downto 0);

--------------------------------------------------------------------------------
-- ALIAS
--------------------------------------------------------------------------------
-- ID
alias id_instr  : std_logic_vector(31 downto 0) is if_id_reg_q.instr;
alias opcode    : std_logic_vector(6 downto 0)  is id_instr(6 downto 0);
alias rd        : std_logic_vector(4 downto 0)  is id_instr(11 downto 7);
alias funct3    : std_logic_vector(2 downto 0)  is id_instr(14 downto 12);
alias rs1       : std_logic_vector(4 downto 0)  is id_instr(19 downto 15);
alias rs2       : std_logic_vector(4 downto 0)  is id_instr(24 downto 20);
alias funct7_b5 : std_logic                     is id_instr(30);
alias id_pc     : std_logic_vector(31 downto 0) is if_id_reg_q.pc;

-- EX
alias ex_alu_src     : std_logic is id_ex_reg_q.alu_src;
alias ex_read_data_1 : std_logic_vector (31 downto 0) is id_ex_reg_q.read_data_1;
alias ex_read_data_2 : std_logic_vector (31 downto 0) is id_ex_reg_q.read_data_2;
alias ex_alu_op      : std_logic_vector(1 downto 0) is id_ex_reg_q.alu_op;
alias ex_imm         : std_logic_vector(31 downto 0) is id_ex_reg_q.imm;
alias ex_funct3      : std_logic_vector(2 downto 0) is id_ex_reg_q.funct3;
alias ex_f7_b5       : std_logic is id_ex_reg_q.funct7_b5;
alias ex_pc          : std_logic_vector(31 downto 0) is id_ex_reg_q.pc;
alias ex_branch      : std_logic is id_ex_reg_q.branch;
signal ex_pc_branch    : std_logic_vector(31 downto 0);
signal ex_zero         : std_logic;
signal ex_ALU_ctrl_s   : std_logic_vector(3 downto 0);
signal ex_alu_mux_out  : std_logic_vector(31 downto 0);
signal ex_alu_result_s : std_logic_vector(31 downto 0);
signal ex_alu_in_a     : std_logic_vector(31 downto 0);
signal ex_alu_in_b     : std_logic_vector(31 downto 0);

-- BYPASS
alias bp_mem_rd      : std_logic_vector(4 downto 0) is ex_mem_reg_q.instr(11 downto 7);
alias bp_ex_rs1      : std_logic_vector(4 downto 0) is ex_mem_reg_d.instr(19 downto 15);
alias bp_ex_rs2      : std_logic_vector(4 downto 0) is ex_mem_reg_d.instr(24 downto 20);
signal bp_alu_result : std_logic_vector(31 downto 0);
signal forwardA      : std_logic_vector(1 downto 0);
signal forwardB      : std_logic_vector(1 downto 0);
alias bp_wb_rd       : std_logic_vector(4 downto 0) is mem_wb_reg_q.rd;
alias bp_wb_regwrite : std_logic is mem_wb_reg_q.reg_write;
signal bp_wb_data     : std_logic_vector(31 downto 0);

-- MEM
alias mem_dm_write   : std_logic is ex_mem_reg_q.mem_write;
alias mem_dm_read    : std_logic is ex_mem_reg_q.mem_read; 
alias mem_alu_result : std_logic_vector(31 downto 0) is ex_mem_reg_q.alu_result;
alias mem_read_data_2: std_logic_vector(31 downto 0) is ex_mem_reg_q.read_data_2;

begin
--------------------------------------------------------------------------------
-- ASSEGNAZIONE DELLE USCITE
--------------------------------------------------------------------------------
instr_obs <= if_id_reg_q.instr; 
pc_obs    <= PC_s;

--------------------------------------------------------------------------------
-- BTB LOGIC
--------------------------------------------------------------------------------
-- Assegnazioni continue degli indici
btb_if_index        <= PC_s(7 downto 2);
btb_ex_update_index <= ex_pc(7 downto 2);

-- FETCH
btb_if_predict_taken <= '1' when (btb(to_integer(unsigned(btb_if_index))).tag = PC_s and 
                               (btb(to_integer(unsigned(btb_if_index))).state = PT or 
                               btb(to_integer(unsigned(btb_if_index))).state = WPT ))
                            else '0';

-- EXECUTE
btb_ex_actual_taken <= ex_zero and ex_branch;

-- XOR per valutare l'errore
btb_ex_error <= (id_ex_reg_q.btb_predict_bit xor btb_ex_actual_taken); --and ex_branch;

btb_ex_pc_fallback <= std_logic_vector(unsigned(ex_pc) + to_unsigned(4,32));

-- se il salto è preso di default passa il branch altrimenti il puntatore all'istruzione successiva 
btb_ex_pc_correction <= ex_pc_branch when btb_ex_actual_taken = '1' else btb_ex_pc_fallback; 

-- processo combinatorio BTB
btb_comb_proc: process(all)
begin
btb_next_state <= WPT;
case btb(to_integer(unsigned(btb_ex_update_index))).state is 
    when PT =>
        if btb_ex_actual_taken = '1' then 
            btb_next_state <= PT;
        else 
            btb_next_state <= WPT;
        end if;
    when WPT => 
        if btb_ex_actual_taken = '1' then 
            btb_next_state <= PT;
        else 
            btb_next_state <= WMP;
        end if;
    when WMP => 
        if btb_ex_actual_taken = '1' then 
            btb_next_state <= WPT;
        else 
            btb_next_state <= MP;
        end if;
    when MP => 
        if btb_ex_actual_taken = '1' then 
            btb_next_state <= WPT;
        else 
            btb_next_state <= MP;
        end if;
    when others => NULL;
end case;
end process;
--------------------------------------------------------------------------------
-- LOGICA PROGRAM COUNTER E FETCH
--------------------------------------------------------------------------------
PC_p4_s   <= std_logic_vector(unsigned(PC_s) + to_unsigned(4, 32));
instruction <= instr_mem(to_integer(unsigned(PC_s(31 downto 2))));

next_pc_logic: process(btb_ex_error, btb_if_predict_taken, btb_ex_pc_correction, PC_p4_s, btb, btb_if_index)
begin
    if btb_ex_error = '1' then 
        PC_next_s <= btb_ex_pc_correction;
    elsif btb_if_predict_taken = '1' then 
        PC_next_s <= btb(to_integer(unsigned(btb_if_index))).target;
    else
        PC_next_s <= PC_p4_s;
    end if;
end process;

--------------------------------------------------------------------------------
-- AVANZAMENTO DELLA PIPELINE E SCRITTURE 
--------------------------------------------------------------------------------
pipeline_update: process(clk)
begin
    if rising_edge(clk) then 
        if reset = '1' then
            PC_s         <= (others => '0');
            if_id_reg_q  <= IF_ID_RESET;
            id_ex_reg_q  <= ID_EX_RESET;
            ex_mem_reg_q <= EX_MEM_RESET; 
            mem_wb_reg_q <= MEM_WB_RESET;
            
            
            
        else 
            PC_s         <= PC_next_s;
            if btb_ex_error = '1' then              -- Logica di Flush
                if_id_reg_q  <= IF_ID_RESET;  -- Flush IF
                id_ex_reg_q  <= ID_EX_RESET;  -- Flush ID
                ex_mem_reg_q <= ex_mem_reg_d; 
                mem_wb_reg_q <= mem_wb_reg_d;
            else
                if_id_reg_q  <= if_id_reg_d;
                id_ex_reg_q  <= id_ex_reg_d;
                ex_mem_reg_q <= ex_mem_reg_d; 
                mem_wb_reg_q <= mem_wb_reg_d;
            end if;
            
            if mem_dm_write = '1' then
                data_mem(to_integer(unsigned(mem_alu_result(31 downto 2)))) <= mem_read_data_2;
            end if;
            
            if mem_wb_reg_q.reg_write = '1' and mem_wb_reg_q.rd /= "00000" then
                reg_file(to_integer(unsigned(mem_wb_reg_q.rd))) <= WB_data_s;
            end if;
            
            -- Addestramento BTB in Execute
            if ex_branch = '1' then
                btb(to_integer(unsigned(btb_ex_update_index))).tag         <= ex_pc;
                btb(to_integer(unsigned(btb_ex_update_index))).target      <= ex_pc_branch;
                btb(to_integer(unsigned(btb_ex_update_index))).state       <= btb_next_state;
            end if;
        end if;
    end if;
end process;

--------------------------------------------------------------------------------
-- LOGICA REGISTRO IF/ID (Stadio Fetch)
--------------------------------------------------------------------------------
if_id_reg_d.pc    <= PC_s;
if_id_reg_d.instr <= instruction;
if_id_reg_d.btb_predict_bit <= btb_if_predict_taken;

--------------------------------------------------------------------------------
-- LOGICA REGISTRO ID/EX (Stadio Decode)
--------------------------------------------------------------------------------
id_ex_reg_d.instr       <= if_id_reg_q.instr;
id_ex_reg_d.pc          <= id_pc;
id_ex_reg_d.btb_predict_bit <= if_id_reg_q.btb_predict_bit;
id_ex_reg_d.rd          <= rd; 
id_ex_reg_d.read_data_1 <= read_data1_s;
id_ex_reg_d.read_data_2 <= read_data2_s;
id_ex_reg_d.funct3      <= funct3;
id_ex_reg_d.funct7_b5   <= funct7_b5;

-- Lettura del register file (Combinatoria asincrona)
read_data1_s <= (others => '0') when rs1 = "00000" else reg_file(to_integer(unsigned(rs1)));
read_data2_s <= (others => '0') when rs2 = "00000" else reg_file(to_integer(unsigned(rs2)));

-- Decodifica dell'istruzione e generazione dell'immediato
decode_imm_gen_logic: process(id_instr)
begin
    id_ex_reg_d.alu_src    <= '0';
    id_ex_reg_d.mem_to_reg <= '0';
    id_ex_reg_d.reg_write  <= '0';
    id_ex_reg_d.mem_read   <= '0';
    id_ex_reg_d.mem_write  <= '0';
    id_ex_reg_d.branch     <= '0';
    id_ex_reg_d.alu_op     <= "00";
    id_ex_reg_d.imm        <= (others => '0');

    -- 1. DECODE DELL'ISTRUZIONE
    case opcode is 
        when OP_IRRI   => 
            id_ex_reg_d.reg_write  <= '1';
            id_ex_reg_d.alu_op     <= "10";
        when OP_LOAD   => 
            id_ex_reg_d.alu_src    <= '1';
            id_ex_reg_d.mem_to_reg <= '1';
            id_ex_reg_d.reg_write  <= '1';
            id_ex_reg_d.mem_read   <= '1';
        when OP_STORE  => 
            id_ex_reg_d.alu_src    <= '1';
            id_ex_reg_d.mem_write  <= '1';
        when OP_BRANCH => 
            id_ex_reg_d.branch     <= '1';
            id_ex_reg_d.alu_op     <= "01";
        when OP_IMM    => 
            id_ex_reg_d.alu_src    <= '1';
            id_ex_reg_d.reg_write  <= '1';
            id_ex_reg_d.alu_op     <= "11";
        when others    => NULL; 
    end case;

    -- 2. CALCOLO DELL'IMMEDIATO
    case opcode is 
        when OP_LOAD | OP_IMM  => 
            id_ex_reg_d.imm(11 downto 0)  <= id_instr(31 downto 20);
            id_ex_reg_d.imm(31 downto 12) <= (others => id_instr(31));
        when OP_STORE  => 
            id_ex_reg_d.imm(11 downto 5)  <= id_instr(31 downto 25);
            id_ex_reg_d.imm(4 downto 0)   <= id_instr(11 downto 7);
            id_ex_reg_d.imm(31 downto 12) <= (others => id_instr(31));
        when OP_BRANCH => 
            id_ex_reg_d.imm(11)           <= id_instr(7);
            id_ex_reg_d.imm(0)            <= '0';
            id_ex_reg_d.imm(10 downto 5)  <= id_instr(30 downto 25);
            id_ex_reg_d.imm(4 downto 1)   <= id_instr(11 downto 8);
            id_ex_reg_d.imm(31 downto 12) <= (others => id_instr(31));
        when others    => NULL;
    end case;
end process;  

--------------------------------------------------------------------------------
-- LOGICA REGISTRO EX/MEM (Stadio Execute)
--------------------------------------------------------------------------------
ex_mem_reg_d.instr       <= id_ex_reg_q.instr;
ex_mem_reg_d.mem_to_reg  <= id_ex_reg_q.mem_to_reg;
ex_mem_reg_d.reg_write   <= id_ex_reg_q.reg_write;
ex_mem_reg_d.mem_read    <= id_ex_reg_q.mem_read;
ex_mem_reg_d.mem_write   <= id_ex_reg_q.mem_write;
ex_mem_reg_d.rd          <= id_ex_reg_q.rd;
ex_mem_reg_d.read_data_2 <= id_ex_reg_q.read_data_2;

-- logica di branch
ex_pc_branch  <= std_logic_vector(signed(ex_pc) + signed(ex_imm));

-- Logica per l'ALU
alu_proc: process(all)
begin
    ex_ALU_ctrl_s   <= "0000";
    ex_alu_result_s <= (others => '0');
    ex_alu_in_a     <= (others => '0');
    ex_alu_in_b     <= (others => '0');
    case ex_alu_op is 
        when "00" => ex_ALU_ctrl_s <= "0010";
        when "01" => ex_ALU_ctrl_s <= "0110";
        when "10" => 
            case ex_funct3 is 
                when F3_ADD  => 
                    if ex_f7_b5 = '1' then 
                        ex_ALU_ctrl_s <= "0110";
                    else 
                        ex_ALU_ctrl_s <= "0010";
                    end if; 
                when F3_AND     => ex_ALU_ctrl_s <= "0000";
                when F3_OR      => ex_ALU_ctrl_s <= "0001";
                when others     => NULL;
            end case;
        when "11" =>
            case ex_funct3 is 
                when F3_ADD     => ex_ALU_ctrl_s <= "0010";
                when F3_AND     => ex_ALU_ctrl_s <= "0000";
                when F3_OR      => ex_ALU_ctrl_s <= "0001";
                when others     => NULL;
            end case;
        when others => NULL;
    end case;

    if forwardA = "10" then
        ex_alu_in_a <= bp_alu_result;  -- Bypass da MEM
    elsif forwardA = "01" then
        ex_alu_in_a <= bp_wb_data;     -- Bypass da WB
    else 
        ex_alu_in_a <= ex_read_data_1;
    end if;

    -- MUX INGRESSO B (Logica del libro + Immediato)
    if ex_alu_src = '1' then
        ex_alu_in_b <= ex_imm;         -- L'immediato vince sempre
    elsif forwardB = "10" then
        ex_alu_in_b <= bp_alu_result;  -- Bypass da MEM
    elsif forwardB = "01" then
        ex_alu_in_b <= bp_wb_data;     -- Bypass da WB
    else 
        ex_alu_in_b <= ex_read_data_2;
    end if;

    case ex_ALU_ctrl_s is 
        when "0000" => 
            ex_alu_result_s <= ex_alu_in_a and ex_alu_in_b;
        when "0001" => 
            ex_alu_result_s <= ex_alu_in_a or ex_alu_in_b;
        when "0010" => 
            ex_alu_result_s <= std_logic_vector(signed(ex_alu_in_a) + signed(ex_alu_in_b));
        when "0110" => 
            ex_alu_result_s <= std_logic_vector(signed(ex_alu_in_a) - signed(ex_alu_in_b));
        when others => 
            ex_alu_result_s <= (others => '0');
    end case;
end process;

ex_mem_reg_d.alu_result <= ex_alu_result_s;
ex_zero         <= '1' when (ex_alu_in_a = ex_alu_in_b) else '0';       -- miglioria 
--------------------------------------------------------------------------------
-- LOGICA DI BYPASS (EX/MEM e MEM/WB)
--------------------------------------------------------------------------------
bp_alu_result <= ex_mem_reg_q.alu_result;

bp_wb_data <= WB_data_s; 

bypass_logic_proc: process(all)
begin
    forwardA <= "00";
    forwardB <= "00";
    
    -- Forward A
    if (ex_mem_reg_q.reg_write = '1') and (bp_mem_rd /= "00000") and (bp_ex_rs1 = bp_mem_rd) then
        forwardA <= "10";
    elsif (bp_wb_regwrite = '1') and (bp_wb_rd /= "00000") and (bp_ex_rs1 = bp_wb_rd) then
        forwardA <= "01";
    end if;

    -- Forward B
    if (ex_mem_reg_q.reg_write = '1') and (bp_mem_rd /= "00000") and (bp_ex_rs2 = bp_mem_rd) then
        forwardB <= "10";
    elsif (bp_wb_regwrite = '1') and (bp_wb_rd /= "00000") and (bp_ex_rs2 = bp_wb_rd) then
        forwardB <= "01";
    end if;
end process;
--------------------------------------------------------------------------------
-- LOGICA REGISTRO MEM/WB (Stadio Memory)
--------------------------------------------------------------------------------
-- Assegnazione dati da propagare
mem_wb_reg_d.reg_write  <= ex_mem_reg_q.reg_write;
mem_wb_reg_d.mem_to_reg <= ex_mem_reg_q.mem_to_reg;
mem_wb_reg_d.alu_result <= mem_alu_result;
mem_wb_reg_d.rd         <= ex_mem_reg_q.rd;

-- Lettura ed assegnazione del dato dalla data memory 
mem_wb_reg_d.data_mem_data <= data_mem(to_integer(unsigned(mem_alu_result(31 downto 2)))) when mem_dm_read = '1' else (others => '0');
--------------------------------------------------------------------------------
-- LOGICA WB (Stadio Writeback)
--------------------------------------------------------------------------------
WB_data_s <= mem_wb_reg_q.data_mem_data when mem_wb_reg_q.mem_to_reg = '1' else mem_wb_reg_q.alu_result;

end Behavioral;
