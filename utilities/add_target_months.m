function adjustedDate = add_target_months(inputDate, nMonths, convention)

%ADD_TARGET_MONTHS Add calendar months and apply TARGET adjustment.
% INPUTS:
%   inputDate  - Datetime object representing the starting date.
%   nMonths    - Integer number of calendar months to add.
%   convention - String specifying the TARGET business-day convention.
%
% OUTPUTS:
%   adjustedDate - Datetime object after adding nMonths and applying the
%                  specified TARGET business-day adjustment.

    if nargin < 3 || isempty(convention)
        convention = 'modifiedfollow';
    end

    rawDate = inputDate + calmonths(nMonths);
    adjustedDate = modifiedFollowing(rawDate);
end
