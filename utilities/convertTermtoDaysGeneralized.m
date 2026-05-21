function t_dates = convertTermtoDaysGeneralized(termStrings, settlementDate)
% CONVERTTERMSTODAYS Converts term strings to actual dates using Modified Following.
%
% Handles two formats:
%   1. Standard tenor strings: '1 DY', '1 WK', '2 MO', '3 YR', etc.
%   2. Euribor futures codes:  'ERN2', 'ERQ2', 'ERU2', 'ERZ3', etc.
%      Format: ER + IMM month letter + 1-digit year (relative to settlementDate)
%      IMM month letters: H=Mar, M=Jun, U=Sep, Z=Dec, N=Jul, Q=Aug, V=Oct, X=Nov
%      Expiry: 3rd Wednesday of expiry month (IMM date convention)
%
% INPUTS:
%   termStrings    - Cell array of strings
%   settlementDate - datetime scalar
%
% OUTPUTS:
%   t_dates - datetime vector of adjusted dates (Modified Following)

% IMM month letter -> month number map
immMonthMap = containers.Map( ...
    {'F','G','H','J','K','M','N','Q','U','V','X','Z'}, ...
    {   1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12});

n = length(termStrings);
t_dates = NaT(n, 1);

for i = 1:n
    term = strtrim(termStrings{i});

    % --- Try standard tenor format first (e.g. '1 WK', '3 MO', '10 YR') ---
    tokens = regexp(term, '^(\d+\.?\d*)\s*(DY|WK|MO|YR)$', 'tokens');

    if ~isempty(tokens)
        num  = str2double(tokens{1}{1});
        unit = tokens{1}{2};

        switch unit
            case 'DY';  rawDate = settlementDate + caldays(num);
            case 'WK';  rawDate = settlementDate + calweeks(num);
            case 'MO';  rawDate = settlementDate + calmonths(num);
            case 'YR';  rawDate = settlementDate + calyears(num);
        end

        t_dates(i) = modifiedFollowing(rawDate);
        continue
    end

    % --- Try Euribor futures code format (e.g. 'ERN2', 'ERM3') ---
    futTokens = regexp(term, '^ER([A-Z])(\d)$', 'tokens');

    if ~isempty(futTokens)
        monthLetter = futTokens{1}{1};
        yearDigit   = str2double(futTokens{1}{2});

        if ~isKey(immMonthMap, monthLetter)
            warning('convertTermToDays:unknownIMMMonth', ...
                'Unknown IMM month letter: "%s" in term "%s"', monthLetter, term);
            continue
        end

        expiryMonth = immMonthMap(monthLetter);

        % Reconstruct full year: take settlement year's decade + digit,
        % roll forward if the resulting date would be before settlementDate
        baseYear = floor(year(settlementDate) / 10) * 10 + yearDigit;
        if baseYear < year(settlementDate)
            baseYear = baseYear + 10;
        end

        % IMM date = 3rd Wednesday of expiry month
        rawDate = thirdWednesday(baseYear, expiryMonth);
        t_dates(i) = modifiedFollowing(rawDate);
        continue
    end

    % --- Unknown format ---
    warning('convertTermToDays:unknownTerm', 'Cannot parse term: "%s"', term);
end

end