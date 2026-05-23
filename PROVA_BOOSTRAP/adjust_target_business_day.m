function adjusted = adjust_target_business_day(dates, convention)
%ADJUST_TARGET_BUSINESS_DAY Backward-compatible wrapper to modifiedFollowing.
% Supported convention: 'modifiedfollow' only.
%
% INPUT:
%   dates       -> datetime or vector of datetime
%   convention  -> string
%
% OUTPUT:
%   adjusted    -> adjusted datetime(s)


    if nargin < 2 || isempty(convention)
        convention = 'modifiedfollow';
    end

    if ~(strcmpi(convention, 'modifiedfollow') || strcmpi(convention, 'modifiedfollowing'))
        error('Unsupported convention: %s. Use modifiedFollowing for Modified Following adjustment.', convention);
    end

    adjusted = modifiedFollowing(dates);
end
