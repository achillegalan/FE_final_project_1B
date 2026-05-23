function t_dates = convertTermToDays(termStrings, settlementDate)
%CONVERTTERMTODAYS Convert market terms to adjusted dates.
%
% INPUTS:
%   termStrings    - Scalar or vector of terms (char/string/cellstr), e.g.
%                    {'1 WK','1 MO','1 YR','ERH3'}.
%   settlementDate - Datetime scalar (curve settlement date).
%
% OUTPUTS:
%   t_dates - Column datetime vector of adjusted dates.

    terms = string(termStrings);
    terms = strtrim(terms(:));

    n = numel(terms);
    t_dates = NaT(n, 1);

    for i = 1:n
        term = upper(terms(i));

        % 3M Futures code (e.g. ERH3 / ERH30)
        if startsWith(term, "ER")
            [~, endDate] = future3mDates(term, settlementDate);
            t_dates(i) = modifiedFollowing(endDate);
            continue
        end

        tokens = regexp(char(term), '^(\d+\.?\d*)\s*(DY|WK|MO|YR)$', 'tokens', 'once');
        if isempty(tokens)
            error('convertTermToDays:unknownTerm', 'Cannot parse term: "%s"', char(term));
        end

        num = str2double(tokens{1});
        unit = tokens{2};

        switch unit
            case 'DY'
                rawDate = settlementDate + caldays(num);
            case 'WK'
                rawDate = settlementDate + calweeks(num);
            case 'MO'
                rawDate = settlementDate + calmonths(num);
            case 'YR'
                rawDate = settlementDate + calyears(num);
            otherwise
                error('convertTermToDays:unknownUnit', 'Unknown unit: "%s"', unit);
        end

        t_dates(i) = modifiedFollowing(rawDate);
    end
end
