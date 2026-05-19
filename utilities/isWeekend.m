function result = isWeekend(dt)
    d = weekday(dt);   % 1=Sun, 7=Sat
    result = (d == 1) || (d == 7);
end