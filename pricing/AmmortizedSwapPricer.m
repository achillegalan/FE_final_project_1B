function swapPrice = AmmortizedSwapPricer( ...
    swapData, oisCurve, pseudoCurve, settlementDate, fixedRate, resetType, knownFixing)

%AMMORTIZEDSWAPPRICER Price an amortizing IRS from the bank perspective.
%
% Computes the risk-free MtM of an amortizing swap:
%   swapPrice = PV(floating leg) - PV(fixed leg)
%
% Inputs:
%   swapData     Table/struct with PayDate, AccrualStart, AccrualEnd, Notional.
%   oisCurve     OIS discounting curve with dates and continuous zeroRates.
%   pseudoCurve  EUR3M projection curve with dates and continuous zeroRates.
%   valuationDate  Pricing date; only PayDate > valuationDate are considered.
%   fixedRate    Fixed coupon rate, in decimal form.
%   resetType    'quarterly' or 'semiannual'. Default: 'quarterly'.
%   knownFixing  Optional struct with resetStartDate and resetRate for
%                already-fixed coupons.
%
% Outputs:
%   swapPrice     Bank MtM: receive floating, pay fixed.

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

%% Keep only future payment flows
check = paymentDates > settlementDate;   % tieni solo pagamenti futuri
payDates = paymentDates(check);
accStart = accrualStartDates(check);
accEnd = accrualEndDates(check);
notional = ammortizedNotional(check);
keptFullIdx = find(check);

%% Map reset dates for kept coupons
resetType = lower(string(strtrim(resetType)));

switch resetType
    case "quarterly"
        resetStart = accStart;
        resetEnd = accEnd;

    case "semiannual"
        % Legacy: stesso 3M fixing del primo trimestre della coppia
        pairStartIdxFull = 2 * ceil(keptFullIdx / 2) - 1;   % 1,1,3,3,...
        resetStart = accrualStartDates(pairStartIdxFull);
        resetEnd = accrualEndDates(pairStartIdxFull);

    otherwise
        error('AmmortizedSwapPricer:InvalidResetType', ...
            'resetType must be ''quarterly'' or ''semiannual''.');
end

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
