
//... put your processor code here
//thank you
//... use your processor code from Part III, and add support for b{cond}
module proc(DIN, Resetn, Clock, Run, DOUT, ADDR, W);
    input [15:0] DIN;//input signal for processor->vary from: memory
    //                                                        switch
    //
    //
    input Resetn, Clock, Run;
    output wire [15:0] DOUT;//data output from processor
    output wire [15:0] ADDR;//address output for address
    output wire W;//write enable signal for memory

    wire [0:7] R_in; // r0, ..., r7 register enables
    reg rX_in, IR_in, ADDR_in, Done, DOUT_in, A_in, G_in, AddSub, ALU_and,ALU_SR,Shift_Select, F_in;//alu_SR signal for shift and rotate 
                                                                                            //
	 /*shift/rotate if ALU_SR=1
	   AddSub or and if ALU_SR=0*/
    reg [2:0] Tstep_Q, Tstep_D;
    reg [15:0] BusWires;
    reg [3:0] Select; // BusWires selector
    reg [15:0] ALU_out;//alu_output without carry out
    reg ALU_cout; //alu carry out signal
    wire [2:0] III, rX, rY; // instruction opcode and register operands
    wire [15:0] r0, r1, r2, r3, r4, r5, r6, pc, A;
    wire [15:0] G;
    wire [15:0] IR;
	wire c,n,z;//flags
    reg pc_incr;    // used to increment the pc
    reg pc_in;      // used to load the pc
    reg W_D;        // used for write signal
    wire Imm;
   
    assign III = IR[15:13];
    assign Imm = IR[12];
    assign rX = IR[11:9];
    assign rY = IR[2:0];
	 //assign Cout=Sum[16];
	 //assign Sum_Out=Sum[15:0];
	 
    dec3to8 decX (rX_in, rX, R_in); // produce r0 - r7 register enables
    

    parameter T0 = 3'b000, T1 = 3'b001, T2 = 3'b010, T3 = 3'b011, T4 = 3'b100, T5 = 3'b101;

    // Control FSM state table
    always @(Tstep_Q, Run, Done)
        case (Tstep_Q)
            T0: // instruction fetch
                if (~Run) Tstep_D = T0;
                else Tstep_D = T1;
            T1: // wait cycle for synchronous memory
                Tstep_D = T2;
            T2: // this time step stores the instruction word in IR
                Tstep_D = T3;
            T3: if (Done) Tstep_D = T0;
                else Tstep_D = T4;
            T4: if (Done) Tstep_D = T0;
                else Tstep_D = T5;
            T5: // instructions end after this time step
                Tstep_D = T0;
            default: Tstep_D = 3'bxxx;
        endcase

    /* OPCODE format: III M XXX DDDDDDDDD, where 
    *     III = instruction, M = Immediate, XXX = rX. If M = 0, DDDDDDDDD = 000000YYY = rY
    *     If M = 1, DDDDDDDDD = #D is the immediate operand 
    *
    *  III M  Instruction   Description
    *  --- -  -----------   -----------
    *  000 0: mv   rX,rY    rX <- rY
    *  000 1: mv   rX,#D    rX <- D (sign extended)
    *  001 1: mvt  rX,#D    rX <- D << 8
    *  010 0: add  rX,rY    rX <- rX + rY
    *  010 1: add  rX,#D    rX <- rX + D
    *  011 0: sub  rX,rY    rX <- rX - rY
    *  011 1: sub  rX,#D    rX <- rX - D
    *  100 0: ld   rX,[rY]  rX <- [rY]
    *  101 0: st   rX,[rY]  [rY] <- rX
    *  110 0: and  rX,rY    rX <- rX & rY
    *  110 1: and  rX,#D    rX <- rX & D 
	 *	 101 1: push rx,[r5]	 r[5]<-rX
	 *  100 1: pop  rx,[r5]  rX <- r[5]
	 *  1111 111 DDDDDDDDD: bl pc<-pc+offset -->check if rX is pc
	 *  111 0: cmp  rX,rY    rX-rY -->only changes flag  
	 *  111 1: cmp  rX,#D	 rX-#D -->only changes flag
	 *  1110XXX10SS00YYY: shift/rotate with register
	 *  1110XXX11SS0DDDD: shift/rotate with immediate data
	 */
	 
	 //instruction encoding
    parameter mv = 3'b000, mvt = 3'b001, add = 3'b010, sub = 3'b011, ld = 3'b100, st = 3'b101,
	     and_ = 3'b110;
		  
	//shift/rotate selectors
	parameter lsl = 00, lsr = 01, ast = 10, ror = 11;
	
    // selectors for the BusWires multiplexer
	 parameter none=3'b000, eq=3'b001,ne=3'b010,cc=3'b011,cs=3'b100,pl=3'b101,mi=3'b110;
    parameter R0_SELECT = 4'b0000, R1_SELECT = 4'b0001, R2_SELECT = 4'b0010, 
        R3_SELECT = 4'b0011, R4_SELECT = 4'b0100, R5_SELECT = 4'b0101, R6_SELECT = 4'b0110, 
        PC_SELECT = 4'b0111, G_SELECT = 4'b1000, 
        SGN_IR8_0_SELECT /* signed-extended immediate data */ = 4'b1001, 
        IR7_0_0_0_SELECT /* immediate data << 8 */ = 4'b1010,
        DIN_SELECT /* data-in from memory */ = 4'b1011;
    // Control FSM outputs
    always @(*) begin
        // default values for control signals
        rX_in = 1'b0; A_in = 1'b0; G_in = 1'b0; IR_in = 1'b0; DOUT_in = 1'b0; ADDR_in = 1'b0; 
        Select = 4'bxxxx; AddSub = 1'b0; ALU_and = 1'b0; W_D = 1'b0; Done = 1'b0;
        pc_in = R_in[7] /* default pc enable */; pc_incr = 1'b0;F_in=1'b0;

        case (Tstep_Q)
            T0: begin // fetch the instruction
                Select = PC_SELECT;  // put pc's content onto the internal bus
                ADDR_in = 1'b1;
                pc_incr = Run; // to increment pc
            end
            T1:; // wait cycle for synchronous memory
                
            T2: // store instruction on DIN in IR 
                IR_in = 1'b1;
            T3: // define signals in T3
                case (III)
                    mv: begin
                        if (!Imm) Select = rY;          // mv rX, rY
                        else Select = SGN_IR8_0_SELECT; // mv rX, #D
                        rX_in = 1'b1;                   // enable the rX register
                        Done = 1'b1;
                    end
                    mvt: begin
                        // ... your code goes here
								if(~Imm) begin
									Select=PC_SELECT;
									A_in=1'b1;
										
								end
								else begin
										rX_in=1'b1;
										Select=IR7_0_0_0_SELECT;
										Done=1'b1;
								end
								
                    end
                    add, sub, and_: begin
                        // ... your code goes here
                        Select=rX;//add rX,rY
                        
                        A_in=1'b1; //store rX or immediate data in A
                    end
                    ld, st: begin
                        // ... your code goes here
                        Select=rY;
                        ADDR_in=1'b1;// store address in rY into address register

                    end
                    default: begin 
								rX_in = 1'b0; A_in = 1'b0; G_in = 1'b0; IR_in = 1'b0; DOUT_in = 1'b0; ADDR_in = 1'b0; 
        Select = 4'bxxxx; AddSub = 1'b0; ALU_and = 1'b0; W_D = 1'b0; Done = 1'b0;
        pc_in = R_in[7] /* default pc enable */; pc_incr = 1'b0;F_in=1'b0;
						  end
                endcase
            T4: // define signals T2
                case (III)
                    add: begin
                        // ... your code goes here
								if(~Imm) begin
									Select=rY;
								end
                       else begin
									Select=SGN_IR8_0_SELECT;
								end
								
                        ALU_and=1'b0;
                        AddSub=1'b0;
								F_in=1'b1;
                        //add mode
                        G_in=1'b1;//store result in G
                    end
						  mvt: begin
								Select=SGN_IR8_0_SELECT;
								G_in=1'b1;
								AddSub=1'b0;
						  end
                    sub: begin
                        // ... your code goes here
                        if(~Imm) begin
									Select=rY;
								end
                       else begin
									Select=SGN_IR8_0_SELECT;
								end
							
                        ALU_and=1'b0;
                        AddSub=1'b1;
								F_in=1'b1;
                        //sub mode
                        G_in=1'b1;//store result in G
                    end
                    and_: begin
                        // ... your code goes here
                        if(~Imm) begin
									Select=rY;
								end
                        else begin
									Select=SGN_IR8_0_SELECT;
								end
							
                        ALU_and=1'b1;
                        AddSub=1'b0;
								F_in=1'b1;
                        //and mode
                        G_in=1'b1;//store result in G
                    end
                    ld: // wait cycle for synchronous memory
                        ;
                    st: begin
                        // ... your code goes here
                        Select=rX;//put data to be written on the bus
                        DOUT_in=1'b1; //store data in the output register
                        W_D=1'b1;//write enable signal
                    end
                    default: begin 
								rX_in = 1'b0; A_in = 1'b0; G_in = 1'b0; IR_in = 1'b0; DOUT_in = 1'b0; ADDR_in = 1'b0; 
        Select = 4'bxxxx; AddSub = 1'b0; ALU_and = 1'b0; W_D = 1'b0; Done = 1'b0;
        pc_in = R_in[7] /* default pc enable */; pc_incr = 1'b0;F_in=1'b0;
						  end
                endcase
            T5: // define T3
                case (III)
                    add, sub, and_: begin
                        // ... your code goes here
                        Select=G_SELECT;
                        rX_in=1'b1;
								
								
                        Done=1'b1;

                    end
                    ld: begin
                        // ... your code goes herex
                        Select=DIN_SELECT;//select the data taken from the memory
                        rX_in=1'b1;//enable the destination register to take in the data
                        Done=1'b1; //instruction done
                    end
                    st: // wait cycle for synhronous memory
                        // ... your code goes here
                        Done=1'b1;
						  mvt:begin
								Select=G_SELECT;
								case(rX)
									none:pc_in=1'b1;
									eq: begin
										if(z) 
											pc_in=1'b1;
											Done=1'b1;
											
									end
									ne: begin
										if(!z)
											pc_in=1'b1;
											Done=1'b1;
									end
									cc:begin
										if(!c)
											pc_in=1'b1;
											Done=1'b1;
									end
									cs:begin
										if(c)
											pc_in=1'b1;
											Done=1'b1;
									end
									pl:begin
										if(!n)
											pc_in=1'b1;
											Done=1'b1;
									end
									mi:begin
										if(n)
											pc_in=1'b1;
											Done=1'b1;
									end
									default:begin
										pc_in=1'b0;Done=1'b0;
									end
									
								endcase
						  end
                        
                    default: begin 
									rX_in = 1'b0; A_in = 1'b0; G_in = 1'b0; IR_in = 1'b0; DOUT_in = 1'b0; ADDR_in = 1'b0; 
        Select = 4'bxxxx; AddSub = 1'b0; ALU_and = 1'b0; W_D = 1'b0; Done = 1'b0;
        pc_in = R_in[7] /* default pc enable */; pc_incr = 1'b0;F_in=1'b0;
						  end
                endcase
            default: begin 
								rX_in = 1'b0; A_in = 1'b0; G_in = 1'b0; IR_in = 1'b0; DOUT_in = 1'b0; ADDR_in = 1'b0; 
        Select = 4'bxxxx; AddSub = 1'b0; ALU_and = 1'b0; W_D = 1'b0; Done = 1'b0;
        pc_in = R_in[7] /* default pc enable */; pc_incr = 1'b0;F_in=1'b0;
						  end
        endcase
    end   
   
    // Control FSM flip-flops
    always @(posedge Clock)
        if (!Resetn)
            Tstep_Q <= T0;
        else
            Tstep_Q <= Tstep_D;   
   
    regn reg_0 (BusWires, Resetn, R_in[0], Clock, r0);
    regn reg_1 (BusWires, Resetn, R_in[1], Clock, r1);
    regn reg_2 (BusWires, Resetn, R_in[2], Clock, r2);
    regn reg_3 (BusWires, Resetn, R_in[3], Clock, r3);
    regn reg_4 (BusWires, Resetn, R_in[4], Clock, r4);
    regn reg_5 (BusWires, Resetn, R_in[5], Clock, r5);
    regn reg_6 (BusWires, Resetn, R_in[6], Clock, r6);
	 

    // r7 is program counter
    // module pc_count(R, Resetn, Clock, E, L, Q);
    pc_count reg_pc (BusWires, Resetn, Clock, pc_incr, pc_in, pc);//if pc_incr, pc=pc+1
                                                                  //if pc_in, pc=BusWires

    regn reg_A (BusWires, Resetn, A_in, Clock, A);
    regn reg_DOUT (BusWires, Resetn, DOUT_in, Clock, DOUT);
    regn reg_ADDR (BusWires, Resetn, ADDR_in, Clock, ADDR);
    regn reg_IR (DIN, Resetn, IR_in, Clock, IR);

    flipflop reg_W (W_D, Resetn, Clock, W);//output write enable signal and maintain it until W_D got changed by the FSM
    
    // alu - support logic shift and algebric manipulation of the data
    always @(*)
        if(ALU_SR)  begin//Shift and rotate if ALU_SR high
            if (Shift_Select == lsl)
                ALU_out = A << shift;
            else if (Shift_Select == lsr) 
                ALU_out = A >> shift;
            else if (Shift_Select == asr) 
                ALU_out = {{16{A[15]}},A} >> shift;    // sign extend
            else // ror
                ALU_out = (A >> shift) | (A << (16 - shift));
        end
        else if(!ALU_SR) begin
            if(!ALU_and)
                if (!AddSub)
                {ALU_cout,ALU_out}= A + BusWires;
                else
                {ALU_cout,ALU_out}= A + ~BusWires + 16'b1;
            else
                {ALU_cout,ALU_out}= A & BusWires;
        end
    regn  reg_G (ALU_out, Resetn, G_in, Clock, G);
	 //F_reg(Cout_In, pos_In, Eq_In, Resetn, F_in, Clock, C,N,Z)
	F_reg regf (ALU_cout, ALU_out[15], ALU_out, Resetn, F_in,Clock,c,n,z);//flag register

    // define the internal processor bus
    // mux for data to be put on Buswires
    always @(*)
        case (Select)
            R0_SELECT: BusWires = r0;
            R1_SELECT: BusWires = r1;
            R2_SELECT: BusWires = r2;
            R3_SELECT: BusWires = r3;
            R4_SELECT: BusWires = r4;
            R5_SELECT: BusWires = r5;
            R6_SELECT: BusWires = r6;
            PC_SELECT: BusWires = pc;
            G_SELECT: BusWires = G;
            SGN_IR8_0_SELECT: BusWires = {{7{IR[8]}}, IR[8:0]}; // sign extended
            IR7_0_0_0_SELECT: BusWires = {IR[7:0], 8'b0};
            DIN_SELECT: BusWires = DIN;
            default: BusWires = 16'bx;
        endcase
endmodule

module pc_count(R, Resetn, Clock, E, L, Q);
    input [15:0] R;
    input Resetn, Clock, E, L;
    output [15:0] Q;
    reg [15:0] Q;
   
    always @(posedge Clock)
        if (!Resetn)
            Q <= 16'b0;
        else if (L)
            Q <= R;
        else if (E)  
            Q <= Q + 1'b1;
endmodule

module dec3to8(E, W, Y);
    input E; // enable
    input [2:0] W;
    output [0:7] Y;
    reg [0:7] Y;
   
    always @(*)
        if (E == 0)
            Y = 8'b00000000;
        else
            case (W)
                3'b000: Y = 8'b10000000;
                3'b001: Y = 8'b01000000;
                3'b010: Y = 8'b00100000;
                3'b011: Y = 8'b00010000;
                3'b100: Y = 8'b00001000;
                3'b101: Y = 8'b00000100;
                3'b110: Y = 8'b00000010;
                3'b111: Y = 8'b00000001;
            endcase
endmodule

module regn(R, Resetn, E, Clock, Q);
    parameter n = 16;
    input [n-1:0] R;
    input Resetn, E, Clock;
    output [n-1:0] Q;
    reg [n-1:0] Q;

    always @(posedge Clock)
        if (!Resetn)
            Q <= 0;
        else if (E)
            Q <= R;
endmodule

module F_reg(Cout_In, pos_In, Eq_In, Resetn, E, Clock, C,N,Z);//syncronize flag regiester 
		input Cout_In;
		input pos_In;
		input [15:0] Eq_In;
		input Clock, E;
		output reg C,N,Z;
		input Resetn;
		//input E;
		
		always@(posedge Clock)
			if (!Resetn) begin
				C<=0;
				N<=0;
				Z<=0;
			end
			else if (E) begin  
				Z<=~(Eq_In[15]|Eq_In[14]|Eq_In[13]|Eq_In[12]|Eq_In[11]|Eq_In[10]|Eq_In[9]|Eq_In[8]|Eq_In[7]|Eq_In[6]|Eq_In[5]|Eq_In[4]|Eq_In[3]|Eq_In[2]|Eq_In[1]|Eq_In[0]);
				N<=pos_In;
				C<=Cout_In;
			end
endmodule
		
		
		
