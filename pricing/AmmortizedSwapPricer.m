function swapPrice = AmmortizedSwapPricer( ...
    swapData, oisCurve, pseudoCurve, settlementDate, fixedRate, resetType, knownFixing)


%COMMENT: Thanks to God the payment dates for both legs are the same ;)
%COMMENT: i will comment better in the docstring, but this filtering of
%pseudodiscounts comes from the annex

% Defaults
if nargin < 6 || isempty(resetType)
    resetType = 'quarterly';
end
if nargin < 7 || isempty(knownFixing)
    knownFixing = struct('resetStartDate', NaT, 'resetRate', NaN);
end


% Extract and shape data
paymentDates       = swapData.PayDate(:);
accrualStartDates  = swapData.AccrualStart(:);
accrualEndDates    = swapData.AccrualEnd(:);
ammortizedNotional = swapData.Notional(:);

curveDates      = oisCurve.dates(:);
zeroRates       = oisCurve.zeroRates(:);
pseudocurveDates = pseudoCurve.dates(:);
pseudozeroRates  = pseudoCurve.zeroRates(:);

knownDates = knownFixing.resetStartDate(:);
knownRates = knownFixing.resetRate(:);

nFull = numel(paymentDates);

%% Map each coupon to its reset start date on FULL schedule
switch resetType
    case "quarterly"
        resetStartFull = accrualStartDates;
        resetEndFull   = accrualEndDates;
    case "semiannual"
        pairStartIdx = 2 * ceil((1:nFull)' / 2) - 1;         % 1,1,3,3,...
        % Legacy convention requested: use the first 3M fixing of each
        % semiannual pair for both quarterly coupons in the pair.
        pairEndIdx   = pairStartIdx;                          
        resetStartFull = accrualStartDates(pairStartIdx);
        resetEndFull   = accrualEndDates(pairEndIdx);
    otherwise
            error('resetType must be ''quarterly'' or ''semiannual''.');
end

%% Keep only future payment flows
check = paymentDates > settlementDate;
payDates = paymentDates(check);
accStart = accrualStartDates(check);
accEnd = accrualEndDates(check);
notional = ammortizedNotional(check);
resetStart = resetStartFull(check);
resetEnd = resetEndFull(check);

%% Year fractions and discounting
yearfracs = yearfrac(accStart, accEnd, 2); % ACT/360
discounts = getTargetDF(settlementDate, curveDates, zeroRates, payDates);

%% Fixed leg
fixedCashFlows = yearfracs .* fixedRate .* notional;
fixedPrice = dot(fixedCashFlows, discounts);

%% Floating leg
floatingRates = zeros(size(yearfracs));

for k = 1:numel(yearfracs)
    if resetStart(k) < settlementDate
        % Coupon already fixed before valuation date -> use known historical fixing
        idxKnown = find(knownDates == resetStart(k), 1);
        floatingRates(k) = knownRates(idxKnown);
    else
        % Project from pseudo-curve
        Pstart = getTargetDF(settlementDate, pseudocurveDates, pseudozeroRates, resetStart(k));
        Pend   = getTargetDF(settlementDate, pseudocurveDates, pseudozeroRates, resetEnd(k));
        deltaReset = yearfrac(resetStart(k), resetEnd(k), 2); % ACT/360 del periodo di reset
        floatingRates(k) = (Pstart / Pend - 1) / deltaReset;
    end
end

floatingCashFlows = floatingRates .* yearfracs .* notional;
floatingPrice = dot(floatingCashFlows, discounts);

%% Bank MtM = receive float - pay fixed
swapPrice = floatingPrice - fixedPrice;

end
