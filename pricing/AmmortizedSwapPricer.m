function swapPrice = AmmortizedSwapPricer( ...
    swapData, oisCurve, pseudoCurve, settlementDate, fixedRate, resetType, knownFixing)

%AMMORTIZEDSWAPPRICER Price an amortizing IRS from the bank perspective.
%
% Computes the risk-free MtM of an amortizing swap:
%   swapPrice = PV(floating leg) - PV(fixed leg)
%
% Inputs:
%   swapData        Table/struct with PayDate, AccrualStart, AccrualEnd, Notional.
%   oisCurve        OIS discounting curve with dates and continuous zeroRates.
%   pseudoCurve     EUR3M projection curve with dates and continuous zeroRates.
%   settlementDate  Pricing date; only PayDate > valuationDate are considered.
%   fixedRate       Fixed coupon rate, in decimal form.
%   resetType       'quarterly' or 'semiannual'. Default: 'quarterly'.
%   knownFixing     Struct with fixingDate and resetRate for
%                   already-fixed coupons.
%
% Outputs:
%   swapPrice       Bank MtM: receive floating, pay fixed.

% Extract and shape data
paymentDates       = swapData.PayDate(:);
accrualStartDates  = swapData.AccrualStart(:);
accrualEndDates    = swapData.AccrualEnd(:);
ammortizedNotional = swapData.Notional(:);

curveDates      = oisCurve.dates(:);
zeroRates       = oisCurve.zeroRates(:);
pseudocurveDates = pseudoCurve.dates(:);
pseudozeroRates  = pseudoCurve.zeroRates(:);

knownDates = knownFixing.fixingDate(:);
knownRates = knownFixing.resetRate(:);

%% Map reset dates on the full schedule
resetType = lower(string(strtrim(resetType)));
nCoupons = numel(paymentDates);
fullIdx = (1:nCoupons).';

switch resetType
    case "quarterly"
        calcStartFull = accrualStartDates;
        calcEndFull   = accrualEndDates;

    case "semiannual"
        % convention: (1,2), (3,4), ... share the first 3M fixing.
        pairStartIdxFull = 2 * ceil(fullIdx / 2) - 1;   % 1,1,3,3,...
        calcStartFull = accrualStartDates(pairStartIdxFull);
        calcEndFull   = accrualEndDates(pairStartIdxFull);
end

% fixing date 2bd prior
fixingDateFull = add_target_business_days(calcStartFull, -2);

%% Floating leg
floatingRatesFull = NaN(nCoupons, 1);

for k = 1:nCoupons
    % Coupons already paid at valuation date are irrelevant for MtM.
    if paymentDates(k) <= settlementDate
        continue;
    end

    if fixingDateFull(k) <= settlementDate
        idxKnown = find(knownDates == fixingDateFull(k), 1);
        floatingRatesFull(k) = knownRates(idxKnown);
    else
        % Future fixing: project from pseudo-curve
        Pstart = getTargetDF(settlementDate, pseudocurveDates, pseudozeroRates, calcStartFull(k));
        Pend   = getTargetDF(settlementDate, pseudocurveDates, pseudozeroRates, calcEndFull(k));
        deltaReset = yearfrac(calcStartFull(k), calcEndFull(k), 2); % ACT/360
        floatingRatesFull(k) = (Pstart / Pend - 1) / deltaReset;
    end
end

%% Keep only future payment flows
check = paymentDates > settlementDate;
payDates = paymentDates(check);
accStart = accrualStartDates(check);
accEnd = accrualEndDates(check);
notional = ammortizedNotional(check);
floatingRates = floatingRatesFull(check);

%% Year fractions and discounting
yearfracs = yearfrac(accStart, accEnd, 2); % ACT/360
discounts = getTargetDF(settlementDate, curveDates, zeroRates, payDates);

%% Fixed leg
fixedCashFlows = yearfracs .* fixedRate .* notional;
fixedPrice = dot(fixedCashFlows, discounts);

floatingCashFlows = floatingRates .* yearfracs .* notional;
floatingPrice = dot(floatingCashFlows, discounts);

%% Bank MtM = receive float - pay fixed
swapPrice = floatingPrice - fixedPrice;

end
