function dates = makeSchedule(startDate, endDate, stepMonths, convention)
%MAKESCHEDULE Generate adjusted schedule from startDate to endDate.
%
% Dates are generated from the original anchor startDate (no iterative drift).
% INPUTS:
%   startDate  - Datetime object representing the schedule start date.
%   endDate    - Datetime object representing the contractual maturity date.
%   stepMonths - Integer number of months between consecutive schedule dates.
%   convention - String specifying the TARGET business-day convention.
%
% OUTPUTS:
%   dates - Column vector of adjusted datetime schedule dates, including
%           startDate and endDate.

    if nargin < 4 || isempty(convention)
        convention = 'modifiedfollow';
    end

    if ~(strcmpi(convention, 'modifiedfollow') || strcmpi(convention, 'modifiedfollowing'))
        error('makeSchedule currently supports only Modified Following convention.');
    end

    dates = startDate;
    k = 1;
    while true
        rawDate = startDate + calmonths(k * stepMonths);

        if rawDate >= endDate
            break
        end

        adjDate = modifiedFollowing(rawDate);
        dates(end+1,1) = adjDate; 
        k = k + 1;
    end

    % Keep the contractual maturity exactly as passed in input.
    if dates(end) ~= endDate
        dates(end+1,1) = endDate;
    end

    % Safety against duplicates after adjustments.
    dates = unique(dates, 'stable');
end
