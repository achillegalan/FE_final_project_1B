function adjustedPaymentDates = modifiedFollowing(unadjustedPaymentDates)
% MODIFIEDFOLLOWING Adjusts a date using the Modified Following convention.
%
%   Advances the input date to the next available business day. However, 
%   if doing so forces the date into the next calendar month, it instead 
%   rolls backward to the previous available business day. This convention 
%   is the strict standard in Euro money markets for FRAs and Swaps.
%
%   INPUTS:
%       unadjustedPaymentDates - Datetime object representing the unadjusted target date.
%
%   OUTPUTS:
%       adjDate - Datetime object adjusted to a valid business day.
%
%   NOTES:
%       - This baseline implementation only accounts for weekends. For full 
%         institutional accuracy, it should be expanded to accept and check 
%         against a holiday calendar (e.g., TARGET2 bank holidays).

adjustedPaymentDates = unadjustedPaymentDates;

adjustedPaymentDates = unadjustedPaymentDates;

% Loop through each date individually
for i = 1:length(unadjustedPaymentDates)
    dt = unadjustedPaymentDates(i);
    
    adjDate = dt; 
    
    % Roll forward 
    while ~is_target_business_day(adjDate)
        adjDate = adjDate + caldays(1);
    end
    
    % Check if we crossed a month boundary
    if month(adjDate) ~= month(dt)
        adjDate = dt; % Reset back to original date
        
        % Roll backward instead
        while ~is_target_business_day(adjDate)
            adjDate = adjDate - caldays(1);
        end
    end
    
    adjustedPaymentDates(i) = adjDate;
end