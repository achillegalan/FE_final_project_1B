function [swapPrice, fixedPrice, floatingPrice] = AmmortizedSwapPricer(paymentDates, ...
    curveDates, pseudocurveDates, ammortizedNotional,zeroRates, pseudozeroRates, fixedRate, settleDate, resetType)

%COMMENT: Thanks to God the payment dates for both legs are the same ;)
%COMMENT: i will comment better in the docstring, but this filtering of
%pseudodiscounts comes from the annex

% reset day is by default quarterly
if nargin < 9 || isempty(resetType)
    resetType = 'quarterly';
end

% Computing yearfracs tenors
allDates = [settleDate; paymentDates];
yearfracs = yearfrac(allDates(1:end-1), allDates(2:end), 2); %Act/360 (look annex)

% Get right (pseudo)Discounts
discounts = getTargetDF(settleDate, curveDates, zeroRates, paymentDates);
pseudodiscounts = getTargetDF(settleDate, pseudocurveDates, pseudozeroRates, paymentDates);

%% Fixed Leg Price
fixedCashFlows = yearfracs .* fixedRate .* ammortizedNotional;
fixedPrice = dot(fixedCashFlows, discounts);

%% Floating Leg Price
% Get fwd pseudoscounts from the spot interpolated ones
pseudodiscountsFull = [1; pseudodiscounts];
pseudoFwdRates = (pseudodiscountsFull(1:end-1) ./ pseudodiscountsFull(2:end) - 1) ./ yearfracs;

resetType = lower(string(resetType));
switch resetType
    case "quarterly"
        appliedFwdRates = pseudoFwdRates;
    case "semiannual"
        nPeriods = numel(pseudoFwdRates);
        pairStartIdx = 2 * ceil((1:nPeriods)' / 2) - 1; % 1,1,3,3,...
        appliedFwdRates = pseudoFwdRates(pairStartIdx);
    otherwise
        error('AmmortizedSwapPricer:InvalidResetType', ...
            'resetType must be ''quarterly'' or ''semiannual''.');
end

floatingCashFlows = appliedFwdRates .* yearfracs .* ammortizedNotional;
floatingPrice = dot(floatingCashFlows, discounts);

swapPrice = floatingPrice - fixedPrice;

end



