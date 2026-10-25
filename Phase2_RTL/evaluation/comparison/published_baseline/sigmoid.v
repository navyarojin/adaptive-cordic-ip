module sigmoid( ck, x, y );
   input ck;
   input signed [ ( `num_bits-1 ):0 ] x;
   output signed [ ( `num_bits-1 ):0 ] y;
   reg signed [ ( 2*`num_bits-1 ):0 ]  tmp, tmp_2, tmp_4;
   reg signed [ ( `num_bits-1 ):0 ]    tmp_3, y_tmp;
   assign y = y_tmp;
   always @ ( posedge ck )
     begin

	if( x <= `xinf )
	  y_tmp = `zero;
	else

	  if( x <= `xmin )
	    begin
	       tmp = `p2k1 * x + `p2k0 * `one;
	       y_tmp = tmp[ ( 2 * `num_bits - 1 - `num_bits_int_part ):`num_bits_frac_part ];
	    end
	  else

	    if( x <= `xmed )
	      begin
		 tmp_2 = `p3k2 * x + `p3k1 * `one;
		 tmp_3 = tmp_2[ ( 2 * `num_bits - 1 - `num_bits_int_part ):`num_bits_frac_part ];
		 tmp_4 = x * tmp_3 + `p3k0 * `one;
		 y_tmp = tmp_4[ ( 2 * `num_bits - 1 - `num_bits_int_part ):`num_bits_frac_part ];
	      end
	    else

	      if( x <= `xmax )
		begin
		   tmp_2 = `p4k2 * x + `p4k1 * `one;
		   tmp_3 = tmp_2[ ( 2 * `num_bits - 1 - `num_bits_int_part ):`num_bits_frac_part ];
		   tmp_4 = x * tmp_3 + `p4k0 * `one;
		   y_tmp = tmp_4[ ( 2 * `num_bits - 1 - `num_bits_int_part ):`num_bits_frac_part ];
		end
	      else

		if( x <= `xsup )
		  begin
		     tmp = `p5k1 * x + `p5k0 * `one;
		     y_tmp = tmp[ ( 2 * `num_bits - 1 - `num_bits_int_part ):`num_bits_frac_part ];
		  end
		else

		  y_tmp = `one;
     end
endmodule
