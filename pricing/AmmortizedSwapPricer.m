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
%   knownFixing     Optional struct with resetStartDate and resetRate for
%                   already-fixed coupons.
%
% Outputs:
%   swapPrice       Bank MtM: receive floating, pay fixed.

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

%% Map reset dates on the FULL schedule first
resetType = lower(string(strtrim(resetType)));
nCoupons = numel(paymentDates);
fullIdx = (1:nCoupons).';

switch resetType
    case "quarterly"
        resetStartFull = accrualStartDates;
        resetEndFull   = accrualEndDates;

    case "semiannual"
        % convention: (1,2), (3,4), ... share the first 3M fixing.
        pairStartIdxFull = 2 * ceil(fullIdx / 2) - 1;   % 1,1,3,3,...
        resetStartFull = accrualStartDates(pairStartIdxFull);
        resetEndFull   = accrualEndDates(pairStartIdxFull);

    otherwise
        error('AmmortizedSwapPricer:InvalidResetType', ...
            'resetType must be ''quarterly'' or ''semiannual''.');
end

%% Build floating rates on the FULL schedule, then cut valuation-relevant cash flows
floatingRatesFull = NaN(nCoupons, 1);

for k = 1:nCoupons
    if resetStartFull(k) < settlementDate
        idxKnown = find(knownDates == resetStartFull(k), 1);
        if ~isempty(idxKnown) && ~isnan(knownRates(idxKnown))
            floatingRatesFull(k) = knownRates(idxKnown);
        end
    else
        Pstart = getTargetDF(settlementDate, pseudocurveDates, pseudozeroRates, resetStartFull(k));
        Pend   = getTargetDF(settlementDate, pseudocurveDates, pseudozeroRates, resetEndFull(k));
        deltaReset = yearfrac(resetStartFull(k), resetEndFull(k), 2); % ACT/360 on reset period
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
