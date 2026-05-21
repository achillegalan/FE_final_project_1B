function d = thirdWednesday(yr, mo)
% Returns the 3rd Wednesday of the given year/month as a datetime
    firstOfMonth = datetime(yr, mo, 1);
    % weekday: 1=Sun, 2=Mon, ..., 4=Wed, ..., 7=Sat
    dow = weekday(firstOfMonth);          % day-of-week of the 1st
    daysToFirstWed = mod(4 - dow, 7);     % days until first Wednesday
    d = firstOfMonth + caldays(daysToFirstWed + 14); % +14 => 3rd Wednesday
end