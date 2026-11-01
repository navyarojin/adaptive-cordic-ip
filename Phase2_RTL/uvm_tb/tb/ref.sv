package activation_reference_pkg;
  function automatic longint signed rounded_div(input longint signed n, d);
    longint signed a, b, q;
    if (d == 0) return 0;
    a = n < 0 ? -n : n;
    b = d < 0 ? -d : d;
    q = (a + b/2) / b;
    return ((n < 0) != (d < 0)) ? -q : q;
  endfunction

  function automatic int signed sat(input longint signed value, input int width);
    longint signed lo, hi;
    lo = -(64'sd1 << (width-1));
    hi = (64'sd1 << (width-1))-1;
    if (value < lo) return int'(lo);
    if (value > hi) return int'(hi);
    return int'(value);
  endfunction

  function automatic int signed activation_fixed(input int signed value,
      input int mode, input int iterations, input bit rounding = 1);
    int indices[16] = '{1,2,3,4,4,5,6,7,8,9,10,11,12,13,13,14};
    int angles[15] = '{0,9000,4185,2059,1025,512,256,128,64,32,16,8,4,2,1};
    int signed x, y, z, xn, yn, direction, shift, reduced, halvings;
    longint signed t, square, denom;
    if (mode == 2) return value < 0 ? 0 : sat(value,16);
    if (mode == 3) return sat(value,16);
    reduced = mode == 1 ? ((value + int'(rounding)) >>> 1) : value;
    if (reduced >= 85197 || reduced <= -85197) begin
      t = reduced > 0 ? 16383 : -16384;
    end else begin
      halvings = 0;
      while (reduced > 16384 || reduced < -16384) begin
        reduced = (reduced + int'(rounding)) >>> 1;
        halvings++;
      end
      x = 16384;
      y = 0;
      z = reduced;
      for (int i = 0; i < iterations; i++) begin
        shift = indices[i];
        direction = z >= 0 ? 1 : -1;
        xn = sat(x + direction * ((y + (rounding ? (1 << (shift-1)) : 0)) >>> shift),18);
        yn = sat(y + direction * ((x + (rounding ? (1 << (shift-1)) : 0)) >>> shift),18);
        z = sat(z - direction * angles[shift],18);
        x = xn;
        y = yn;
      end
      t = rounded_div(64'(y) * 16384, x);
      repeat (halvings) begin
        square = rounded_div(t*t,16384);
        denom = 16384 + square;
        t = rounded_div(2*t*16384,denom);
      end
      t = sat(t,16);
    end
    if (mode == 1) t = (16384 + t + int'(rounding)) >>> 1;
    return sat(t,16);
  endfunction
endpackage
