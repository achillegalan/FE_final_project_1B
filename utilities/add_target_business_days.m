function d_out = add_target_business_days(d_in, n)

%ADD_TARGET_BUSINESS_DAYS Adds or subtracts TARGET business days from a date.
%
% INPUTS:
%   d_in    Initial date, as datetime or serial date number.
%   n       Number of TARGET business days to move. Positive values move
%           forward, negative values move backward, and zero returns d_in.
%
% OUTPUT:
%   d_out   Date obtained by moving n TARGET business days from d_in,
%           skipping weekends and TARGET holidays.

if n == 0
    d_out = d_in;
    return;
end

d_out = d_in;
step = sign(n);
remaining = abs(n);

while remaining > 0
    if isdatetime(d_out)
        d_out = d_out + caldays(step);
    else
        d_out = d_out + step;
    end
    if is_target_business_day(d_out)
        remaining = remaining - 1;
    end
end

end