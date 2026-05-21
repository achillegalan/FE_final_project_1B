function d = thirdWednesday(yearNumber, monthNumber)
%THIRDWEDNESDAY Third Wednesday of a given month.
% INPUTS:
%   yearNumber  - Integer year.
%   monthNumber - Integer month number, from 1 to 12.
%
% OUTPUTS:
%   d - Datetime object corresponding to the third Wednesday of the
%       specified month and year.

    firstDay = datetime(yearNumber, monthNumber, 1);
    allDays = firstDay : caldays(1) : dateshift(firstDay, 'end', 'month');
    isWed = weekday(allDays) == 4;
    wednesdays = allDays(isWed);
    d = wednesdays(3);

end