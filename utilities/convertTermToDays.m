function t_dates = convertTermToDays(termStrings, settlementDate)
% CONVERTTERMSTODAYS Converts term strings to actual dates using Modified Following.
%
% INPUTS:
%   termStrings    - Cell array of strings e.g. {'1 WK','1 MO','1 YR'}
%   settlementDate - datetime scalar (e.g. datetime(2023,1,31))
%
% OUTPUTS:
%   t_dates - datetime vector of adjusted dates (Modified Following)

n = length(termStrings);
t_dates = NaT(n, 1);   % preallocate as datetime array

for i = 1:n
    term = strtrim(termStrings{i});

    % Parse number and unit
    tokens = regexp(term, '^(\d+\.?\d*)\s*(DY|WK|MO|YR)$', 'tokens');

    if isempty(tokens)
        warning('convertTermsToDays:unknownTerm', 'Cannot parse term: "%s"', term);
        continue
    end

    num  = str2double(tokens{1}{1});
    unit = tokens{1}{2};

    % Add duration to settlement date
    switch unit
        case 'DY';  rawDate = settlementDate + caldays(num);
        case 'WK';  rawDate = settlementDate + calweeks(num);
        case 'MO';  rawDate = settlementDate + calmonths(num);
        case 'YR';  rawDate = settlementDate + calyears(num);
        otherwise
            warning('convertTermsToDays:unknownUnit', 'Unknown unit: "%s"', unit);
            continue
    end

    t_dates(i) = modifiedFollowing(rawDate);
end

end
