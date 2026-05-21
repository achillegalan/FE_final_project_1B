function adjDate = modifiedFollowing(dt)
% MODIFIEDFOLLOWING Adjusts a date using the Modified Following convention.
%
%   Advances the input date to the next available business day. However, 
%   if doing so forces the date into the next calendar month, it instead 
%   rolls backward to the previous available business day. This convention 
%   is the strict standard in Euro money markets for FRAs and Swaps.
%
%   INPUTS:
%       dt      - Datetime object representing the unadjusted target date.
%
%   OUTPUTS:
%       adjDate - Datetime object adjusted to a valid business day.
%
%   NOTES:
%       - This baseline implementation only accounts for weekends. For full 
%         institutional accuracy, it should be expanded to accept and check 
%         against a holiday calendar (e.g., TARGET2 bank holidays).

% Supports scalar or array datetime inputs.
    adjDate = dt;

    for i = 1:numel(dt)
        d = dt(i);

        % Adjust to next business day.
        while ~is_target_business_day(d)
            d = d + caldays(1);
        end

        % If we crossed into a new month, roll backward instead.
        if month(d) ~= month(dt(i))
            d = dt(i);
            while ~is_target_business_day(d)
                d = d - caldays(1);
            end
        end

        adjDate(i) = d;
    end
end