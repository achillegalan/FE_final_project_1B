function tf = is_target_business_day(dates)

%IS_TARGET_BUSINESS_DAY Checks whether dates are TARGET business days.
%
% INPUT:
%   dates   Datetime array or serial date numbers to check.
%
% OUTPUT:
%   tf      Logical array with the same size as dates. Each element is true
%           if the corresponding date is not a weekend and not a TARGET
%           holiday; false otherwise.

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
