function [startDate, endDate] = future3mDates(code, settlementDate)
%FUTURE3MDATES Return start/end dates of a 3M Euribor future (decade-aware).
% INPUTS:
%   code           - String or char array identifying the 3M Euribor future
%                    code, e.g. 'ERN2', 'ERH30'.
%   settlementDate - Datetime object used to infer the decade when the future
%                    code has a one-digit year.
%
% OUTPUTS:
%   startDate - Datetime object corresponding to the IMM start date of the future.
%   endDate   - Datetime object corresponding to the IMM end date, three months
%               after startDate.

    code = upper(strtrim(char(string(code))));
    tk = regexp(code, '^ER([FGHJKMNQUVXZ])(\d{1,2})$', 'tokens', 'once');
    if isempty(tk)
        error('Invalid future code format: %s', code);
    end

    monthLetter = tk{1};
    yearToken   = tk{2};
    monthNumber = monthLetterToNumber(monthLetter);

    if numel(yearToken) == 2
        yearNumber = 2000 + str2double(yearToken);   % es: H30 -> 2030
    else
        d = str2double(yearToken);                   % es: H0
        ySet = year(settlementDate);
        decade0 = 10 * floor(ySet / 10);
        candidates = [decade0 - 10 + d, decade0 + d, decade0 + 10 + d];

        % scegli l'anno più vicino al settlement
        [~, j] = min(abs(candidates - ySet));
        yearNumber = candidates(j);
    end

    startDate = thirdWednesday(yearNumber, monthNumber);

    endMonthNumber = monthNumber + 3;
    endYearNumber  = yearNumber + floor((endMonthNumber - 1) / 12);
    endMonthNumber = mod(endMonthNumber - 1, 12) + 1;
    endDate = thirdWednesday(endYearNumber, endMonthNumber);
end

function monthNumber = monthLetterToNumber(letter)
%MONTHLETTERTONUMBER Convert futures month code to calendar month.

    switch upper(char(letter))
        case 'F'
            monthNumber = 1;
        case 'G'
            monthNumber = 2;
        case 'H'
            monthNumber = 3;
        case 'J'
            monthNumber = 4;
        case 'K'
            monthNumber = 5;
        case 'M'
            monthNumber = 6;
        case 'N'
            monthNumber = 7;
        case 'Q'
            monthNumber = 8;
        case 'U'
            monthNumber = 9;
        case 'V'
            monthNumber = 10;
        case 'X'
            monthNumber = 11;
        case 'Z'
            monthNumber = 12;
        otherwise
            error('future3mDates:unknownMonthLetter', ...
                'Unknown futures month letter: %s', letter);
    end
end
