`timescale 1ns / 1ns // `timescale time_unit/time_precision


/* drawlines.v
 *
 * Top level entity for the drawlines circuits.
 * Inputs:
 * - SW[8:0] - a value for X or Y coordinate. Should be between 0 and 319 for X and 0 to 239 for Y.
 * - SW[9] 	 - specify if X or Y is beign entered (0 for X and 1 for Y)
 * - KEY[2]  - press to signal that the new point is now ready (GO).
 * - KEY[1]  - press to store the X or Y coordinate of the new point.
 * - KEY[0]  - asynchronous reset. Press the button to reset the system.
 * Outputs:
 * - lines display on a monitor
 * - LEDR[9] is lit up when new point can be entered.
 */

module drawlines(
			SW,
			CLOCK_50,
			LEDR,
			KEY,
			VGA_R,
			VGA_G,
			VGA_B,
			VGA_HS,
			VGA_VS,
			VGA_BLANK,
			VGA_SYNC,
			VGA_CLK, HEX0, HEX1, HEX2, HEX3, HEX4, HEX5);
	input [9:0] SW;
	input [3:0] KEY;
	input CLOCK_50;
	output [9:0] LEDR;
	output [9:0] VGA_R;
	output [9:0] VGA_G;
	output [9:0] VGA_B;
	output	VGA_HS,
			VGA_VS,
			VGA_BLANK,
			VGA_SYNC,
			VGA_CLK;
	output [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5; 
			
	/* Local wires to connect modules together */
	//INPUTS
	wire       resetN;
	wire       XorY_sel, XorY_store;
	wire [8:0] XorY_val;
	wire [2:0] colour;
	assign resetN     = KEY[0];
	assign XorY_store = KEY[1];
	//assign go         = KEY[2];
	assign XorY_val   = SW[8:0];
	assign XorY_sel   = SW[9];
	assign colour     = 3'b101;
	//UI <--> LDA
	reg       line_go, line_done;
	reg [8:0] X_0, X_1, X_in;
	reg [8:0] Y_0, Y_1, Y_in;
	//LDA <--> VGA
	reg [8:0] to_VGA_x;
	reg [7:0] to_VGA_y;
	reg       plot;

	reg line_go_save;
	wire go;
	
	vga_adapter VGA(
				.resetn(resetN),
				.clock(CLOCK_50),
				.colour(colour),
				.x(to_VGA_x),
				.y(to_VGA_y),
				.plot(plot),
				.VGA_R(VGA_R),
				.VGA_G(VGA_G),
				.VGA_B(VGA_B),
				.VGA_HS(VGA_HS),
				.VGA_VS(VGA_VS),
				.VGA_BLANK(VGA_BLANK),
				.VGA_SYNC(VGA_SYNC),
				.VGA_CLK(VGA_CLK));
			defparam VGA.RESOLUTION = "320x240";				
			defparam VGA.MONOCHROME = "FALSE";
			defparam VGA.BITS_PER_COLOUR_CHANNEL = 1;	
			defparam VGA.BACKGROUND_IMAGE = "background.mif";

	/* Line algorithm FSM */
	parameter [9:0] get_steep_S = 10'b0000000001, compareSteep_S = 10'b0000000010, swapXandY_S = 10'b0000000100, swapX_S = 10'b0000001000, initializeVariables_S = 10'b0000010000, plot_S = 10'b0000100000,
		increment_S = 10'b0001000000, checkDone_S = 10'b0010000000, done_S = 10'b0100000000, wait_S = 10'b1000000000, checkForSwapX_S = 10'b1000000001;
	
	reg steep, loadCounter, enableCounter, loadError, incrementX, incrementY, calculateXError, calculateYError, swapXandYEnable, swapXEnable, resetXandY, calculateSteep, loadPosition,
		calculateDelta, enableGo, disableGo;
	wire error_gt_0, x_lt_x1;
	reg [8:0] xPosition, initialX;
	reg [8:0] yPosition, initialY;
	reg [8:0] deltaX;
	reg [9:0] error;
	reg [8:0] deltaY;
	reg [9:0] currentState, nextState;
	reg yStep;
	
	wire x0_gt_x1;
	assign  x0_gt_x1 = (X_0 > X_1);
	
	always@(*) begin
		case(currentState) 
			wait_S: begin
				if (line_go)
					nextState = get_steep_S;
				else
					nextState = wait_S;
			end
			//LDA FSM 
			//state for setting steep value depending on x and y positions
			get_steep_S: begin
				nextState = compareSteep_S;
			end
			compareSteep_S: begin
				if (steep) nextState = swapXandY_S;
				else if (x0_gt_x1) nextState = swapX_S;
				else nextState = initializeVariables_S;
			end
			swapXandY_S: begin
				 nextState  = checkForSwapX_S;
			end
			checkForSwapX_S:
				if (x0_gt_x1) nextState = swapX_S;
				else nextState = initializeVariables_S;
			swapX_S: begin
				nextState = initializeVariables_S;
			end
			initializeVariables_S: begin
				nextState = plot_S;
			end
			plot_S: begin
				nextState = increment_S;
			end
			increment_S: begin //also re-comutes error and increment x counter and y 
				nextState = checkDone_S;
			end
			checkDone_S: begin
				if (xPosition <= X_1)
					nextState = plot_S;
				else
					nextState = done_S;
			end
			done_S: begin
				//if (line_go)
					nextState = wait_S;
				//else
				//	nextState = done_S;
			end
			default: nextState = wait_S;
		
		endcase
	end
	
	
	
	always@(*) begin
	//default condition
		swapXandYEnable = 0;
		swapXEnable = 0;
		loadCounter = 0;
		enableCounter = 0;
		plot = 0;
		loadError = 0;
		incrementX = 0;
		incrementY = 0;
		calculateXError = 0;
		calculateYError = 0;
		line_done = 0;
		resetXandY = 0;
		calculateSteep = 0;
		calculateDelta = 0;
		loadPosition = 0;
		disableGo = 0;
		case(currentState) 
		
			//state for setting steep value depending on x and y positions
			get_steep_S: begin
				calculateSteep = 1;
				
			end
			
		
			swapXandY_S: begin 
				swapXandYEnable = 1;
			end
			swapX_S: begin
				swapXEnable = 1;
			end
			initializeVariables_S: begin
				loadError = 1;
				resetXandY = 1;
				calculateDelta = 1;
			end
			plot_S: begin
				plot = 1;
				calculateYError = 1;
				loadPosition = 1;
			end
			increment_S: begin
				if (error_gt_0) begin
					incrementY = 1;
					calculateXError = 1;
				end
				else begin
					incrementY = 0;
					calculateXError = 0;
				end
				incrementX = 1;
			end
			checkDone_S: begin
				disableGo = 1;
			end
			done_S: begin	
				line_done = 1;
				end
			default: plot = 0;
		endcase

	end

	reg [15:0] currentStateUI, nextStateUI;
	reg load, resetPosition, update;
	/* User interface */
	parameter [15:0] reset_S = 16'b0000010000000000, load_S = 16'b0000100000000000, go_S = 16'b0001000000000000, updatePosition_S = 16'b0010000000000000, waitInput_S = 16'b0100000000000000, waitLDA_S = 16'b1000000000000000;

	
	always@(posedge CLOCK_50, negedge resetN) begin
		if (~resetN) begin
			currentState = wait_S;
			currentStateUI = reset_S;
		end
		else begin
			currentState = nextState;
			currentStateUI = nextStateUI;
		end
	end
	
	//UI FSM
	
	always@(*) begin
		case(currentStateUI) 
			reset_S: begin
				nextStateUI = waitInput_S;
			end
			waitInput_S: begin
				if (!XorY_store) begin
					nextStateUI = load_S;
				end	
				else if (!go && line_go_save) begin
					nextStateUI = go_S;
				end
				else begin
					nextStateUI = waitInput_S;
				end
			end
			load_S: begin
				nextStateUI = waitInput_S;
			end
			go_S: begin
				nextStateUI = waitLDA_S;
			end
			waitLDA_S: begin
				if (line_done)
					nextStateUI = updatePosition_S;
				else
					nextStateUI = waitLDA_S;
			end
			updatePosition_S: begin
				nextStateUI = waitInput_S;
			end
			default: nextStateUI = reset_S;
		endcase

	end
	
	always@(*) begin
		line_go = 0;
		case(currentStateUI) 
			reset_S: begin
				resetPosition = 1;
				update = 0;
				//enableGo = 0;
				load = 0;
			end
			waitInput_S: begin
				resetPosition = 0;
				update = 0;
				enableGo = 0;
				load = 0;
			end
			load_S: begin
				resetPosition = 0;
				update = 0;
				//enableGo = 0;
				load = 1;
			end
			go_S: begin
				resetPosition = 0;
				update = 0;
				line_go = 1;
				load = 0;
			end
			waitLDA_S: begin
				resetPosition = 0;
				update = 0;
				line_go = 0;
				load = 0;
			end
			updatePosition_S: begin
				resetPosition = 0;
				update = 1;
				//enableGo = 0;
				load = 0;
			end
		endcase

	end

				
	/* Circuit outputs. */
	
/* 	always@(posedge CLOCK_50, negedge resetN) begin
		if (!resetN)
			line_go <= 0;
		else if (disableGo)
			line_go <= 0;
		else if (enableGo)
			line_go <= 1;
		
	end
	 */
	
	//datapath for swaping values
	always@(posedge CLOCK_50) begin
		if (resetPosition) begin
			X_0 <= 0;
			Y_0 <= 0;
			X_1 <= 0;
			Y_1 <= 0;
			initialX <= 0;
			initialY <= 0;
		end
		else if (load) begin
			if (XorY_sel) begin
				X_1[8:0] <= XorY_val[8:0];
				initialX <= XorY_val;
			end
			else begin
				Y_1 <= {1'b0, XorY_val[7:0]};
				initialY <= XorY_val;
			end
		end
		else if (update) begin
			X_0[8:0] <= initialX[8:0];
			Y_0[8:0] <= {1'b0, initialY[7:0]};
			X_1[8:0] <= initialX[8:0];
			Y_1[8:0] <= {1'b0, initialY[7:0]};
		end
		else if (swapXandYEnable) begin
			X_0 <= Y_0;
			Y_0 <= X_0;
			X_1 <= Y_1;
			Y_1 <= X_1;
		end
		else if (swapXEnable) begin
			X_0 <= X_1;
			X_1 <= X_0;
			Y_0 <= Y_1;
			Y_1 <= Y_0;
		end
	end
	
	
	assign go = KEY[2];
	//edge detection for go signal
	always@(posedge CLOCK_50, negedge resetN) begin
		if (!resetN) begin
			line_go_save <= 1;
		end
		else begin
			line_go_save <= KEY[2];
		end
		/* else if (!key[2] && line_go_save) begin
			go <= 0;
		end
		else begin
			go <= 1;
		end
		 */
			
	end
	
	assign error_gt_0 = ((0 < error) && (error <= 9'd511));
	//assign x_lt_x1 = (xPosition <= X_1);
	//caclulating error value
	always@(posedge CLOCK_50, negedge resetN) begin
		if (!resetN) 
			error <= 0;
		else if (loadError)
			error <= {1'b0,(~(deltaX >>1))+1};
		else if (calculateYError)
			error <= error + {deltaY[8], deltaY};
		else if (calculateXError)	
			error <= error + ~{1'b0, deltaX} + 1'b1; //find 2's complement of deltaX because we are subtracting
	end
	
	//calculating x and y positions
	always@(posedge CLOCK_50) begin
		if (resetXandY) begin
			xPosition <= X_0;
			yPosition <= Y_0;
		end
		if (incrementX)
			xPosition <= xPosition + 1;
		if (incrementY) begin
			if(yStep) 
				yPosition <= yPosition + 9'd1;
			else 
				yPosition <= yPosition - 1;
		end
	end
	
	//load toVGA
	always@(posedge CLOCK_50, negedge resetN) begin
		if (!resetN) begin
			to_VGA_x <= 0;
			to_VGA_y <= 0;
		end
		else if (loadPosition) begin
			if (steep) begin
				to_VGA_x[8:0] <=  yPosition[8:0];
				to_VGA_y[7:0] <= xPosition[7:0];
			end
			else begin
				to_VGA_x[8:0] <= xPosition[8:0];
				to_VGA_y[7:0] <= yPosition[7:0];
			end
		end
	end
	
	//calculating steep
	always@(posedge CLOCK_50, negedge resetN) begin
		if (!resetN)
			steep <= 0;
		else if (calculateSteep) begin
			if (Y_1 > Y_0) begin
				if (X_1 > X_0) begin
					steep <= ((Y_1 - Y_0) > (X_1 - X_0));
				end
				else begin
					steep <= ((Y_1 - Y_0) > (X_0 - X_1));
				end
			end
			else begin
				if (X_1 > X_0) begin
					steep <= ((Y_0 - Y_1) > (X_1 - X_0));
				end
				else begin
					steep <= ((Y_0 - Y_1) > (X_0 - X_1));
				end
			end
		end
	end
	
	//calculating deltaX, deltaY, yStep
	always@(posedge CLOCK_50, negedge resetN) begin
		if (!resetN) begin
			deltaX <= 0;
			deltaY <= 0;
			yStep <= 0;
		end
		else if (calculateDelta) begin
			if (Y_0 < Y_1) begin
				deltaY <= Y_1 - Y_0;
				yStep <= 1;
			end
			else begin
				deltaY <= Y_0 - Y_1;
				yStep <= 0;
			end
			deltaX <= X_1 - X_0;
		end
	end
	
	
	
	//display x values and values on hex_LEDs
	//hex_digits h0(X_1[3:0], HEX0);
	//hex_digits h1(X_1[7:4], HEX1);
	//hex_digits h2(Y_1[3:0], HEX2);
	//hex_digits h3(Y_1[7:4], HEX3);
	//hex_digits h4(X_0[3:0], HEX4);
	//hex_digits h5(Y_0[3:0], HEX5);
	
	assign LEDR[9:0] = currentState[9:0];
	
endmodule


module hex_digits(x, hex_LEDs);
	input [3:0] x;
	output [6:0] hex_LEDs;
	
	assign hex_LEDs[0] = 	(~x[3] & ~x[2] & ~x[1] & x[0]) |
							(~x[3] & x[2] & ~x[1] & ~x[0]) |
							(x[3] & x[2] & ~x[1] & x[0]) |
							(x[3] & ~x[2] & x[1] & x[0]);
	assign hex_LEDs[1] = 	(~x[3] & x[2] & ~x[1] & x[0]) |
							(x[3] & x[1] & x[0]) |
							(x[3] & x[2] & ~x[0]) |
							(x[2] & x[1] & ~x[0]);
	assign hex_LEDs[2] = 	(x[3] & x[2] & ~x[0]) |
							(x[3] & x[2] & x[1]) |
							(~x[3] & ~x[2] & x[1] & ~x[0]);
	assign hex_LEDs[3] =	(~x[3] & ~x[2] & ~x[1] & x[0]) | 
							(~x[3] & x[2] & ~x[1] & ~x[0]) | 
							(x[2] & x[1] & x[0]) | 
							(x[3] & ~x[2] & x[1] & ~x[0]);
	assign hex_LEDs[4] = 	(~x[3] & x[0]) |
							(~x[3] & x[2] & ~x[1]) |
							(~x[2] & ~x[1] & x[0]);
	assign hex_LEDs[5] = 	(~x[3] & ~x[2] & x[0]) | 
							(~x[3] & ~x[2] & x[1]) | 
							(~x[3] & x[1] & x[0]) | 
							(x[3] & x[2] & ~x[1] & x[0]);
	assign hex_LEDs[6] = 	(~x[3] & ~x[2] & ~x[1]) | 
							(x[3] & x[2] & ~x[1] & ~x[0]) | 
							(~x[3] & x[2] & x[1] & x[0]);
	
endmodule
		