function d_out = add_target_business_days(d_in, n)
% add_target_business_days  Add/subtract TARGET business days.
%
% d_out = add_target_business_days(d_in, n)
%
% If n > 0, moves forward by n TARGET business days.
% If n < 0, moves backward by abs(n) TARGET business days.
% If n = 0, returns the input date.

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