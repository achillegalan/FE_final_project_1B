function tf = is_target_business_day(dates)
% is_target_business_day  True for TARGET business days.

tf = true(size(dates));
if isempty(dates)
    return;
end

if isdatetime(dates)
    dateNums = datenum(dates);
else
    dateNums = dates;
end

holidayList = target_holidays(min(dateNums(:)) - 10, max(dateNums(:)) + 10);
holidayDays = floor(holidayList);
for k = 1:numel(dates)
    w = weekday(dates(k));
    isWeekend = (w == 1 || w == 7);
    isHoliday = any(holidayDays == floor(dateNums(k)));
    tf(k) = ~(isWeekend || isHoliday);
end

end
