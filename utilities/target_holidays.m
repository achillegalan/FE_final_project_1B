function h = target_holidays(startDate, endDate)
% target_holidays  TARGET closing days for a date interval.
%
% TARGET is closed on Saturdays, Sundays, New Year's Day, Good Friday,
% Easter Monday, Labour Day, Christmas Day and Boxing Day. Weekends are
% handled separately by is_target_business_day; this function returns the
% fixed and Easter-related holidays only.

startYear = datevec(startDate);
endYear   = datevec(endDate);
years = startYear(1):endYear(1);

h = zeros(numel(years) * 6, 1);
pos = 1;
for y = years
    easterSunday = easter_sunday(y);
    h(pos:pos+5) = [
        datenum(y, 1, 1);
        easterSunday - 2;
        easterSunday + 1;
        datenum(y, 5, 1);
        datenum(y, 12, 25);
        datenum(y, 12, 26)
    ];
    pos = pos + 6;
end

h = unique(h);
h = h(h >= floor(startDate) & h <= ceil(endDate));

end


function e = easter_sunday(y)
% Gregorian computus, valid for modern TARGET dates.
a = mod(y, 19);
b = floor(y / 100);
c = mod(y, 100);
d = floor(b / 4);
e0 = mod(b, 4);
f = floor((b + 8) / 25);
g = floor((b - f + 1) / 3);
h = mod(19 * a + b - d - g + 15, 30);
i = floor(c / 4);
k = mod(c, 4);
l = mod(32 + 2 * e0 + 2 * i - h - k, 7);
m = floor((a + 11 * h + 22 * l) / 451);
month = floor((h + l - 7 * m + 114) / 31);
day = mod(h + l - 7 * m + 114, 31) + 1;
e = datenum(y, month, day);
end
