function dateOut = termToDate(term, settlementDate)

%TERMTODATE Backward-compatible wrapper around convertTermToDays.
% INPUTS:
%   term           - String or char array representing the market term
%                    (e.g. '1 DY', '1 WK', '3 MO', '5 YR', 'ERN2').
%   settlementDate - Datetime object representing the curve settlement date.
%
% OUTPUTS:
%   dateOut - Datetime object corresponding to the adjusted maturity date.

    % Backward-compatible wrapper: single term -> single date
    dateOut = convertTermToDays(string(term), settlementDate);
    dateOut = dateOut(1);
end
