function price = bachelierPSSwaptionPricer( ...
    OIS_curve, EUR3M_curve, paymentDates, strike, normalVol, exerciseDate, Notional, isPayer, fixingFrequency)
%BACHELIERPSSWAPTIONPRICER Physical-settlement swaption under Bachelier.

settleDate = OIS_curve.settlementDate;

% Calculate TTM for volatility interpolation strictly as ACT/365
TTM = yearfrac(settleDate, exerciseDate, 3); 

paymentDates = paymentDates(:);
Notional = Notional(:);

% Filter the actual valid payment days to compute the quantities of interest
remainingPayments = paymentDates > exerciseDate;
paymentDates = paymentDates(remainingPayments);
remainingNotional = Notional(remainingPayments);

% Safe return check if there's no underlying swap duration left
if isempty(paymentDates)
    price = 0;
    return;
end

% Interpolation to get the right discounts
accrualStartDates = [exerciseDate; paymentDates(1:end-1)];
yearFracs = yearfrac(accrualStartDates, paymentDates, 2); % ACT/360

% Discounting
optionDiscount = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, exerciseDate);
paymentDiscounts = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, paymentDates);
fwdDiscounts = paymentDiscounts ./ optionDiscount;

% Pseudo - Discounting
pseudoDiscounts = getTargetDF(settleDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, paymentDates);
pseudoDiscountsAtExpiry = getTargetDF(settleDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, exerciseDate);
pseudoDiscountsFull = [pseudoDiscountsAtExpiry; pseudoDiscounts];

quarterlyFwdRates = (pseudoDiscountsFull(1:end-1) ./ pseudoDiscountsFull(2:end) - 1) ./ yearFracs;

% Fix: Replaced string comparison (==) with strcmpi to prevent char array issues
if strcmpi(fixingFrequency, 'semiannual')
    fixingRates = quarterlyFwdRates;
    fixingRates(2:2:end) = quarterlyFwdRates(1:2:end-1);
else
    fixingRates = quarterlyFwdRates;
end

% Computing Ammortized BPV and Swap Rate
ammortizedNotional = remainingNotional ./ remainingNotional(1);
ammortizedBPV = sum(yearFracs .* ammortizedNotional .* fwdDiscounts);

floatingLegFwdValue = sum(fwdDiscounts .* yearFracs .* ...
    ammortizedNotional .* fixingRates);

ammortizedFwdSwapRate = floatingLegFwdValue / ammortizedBPV;

% =========================================================================
% VOLATILITY MAPPING VIA BPV INTERPOLATION
% =========================================================================

volsAtExpiry = interp1(normalVol.expiriesNum, normalVol.matrixDecimal, TTM, 'linear');
maxTenor = max(normalVol.tenorsNum); % Max is typically 30Y
vanillaPaymentDates = NaT(maxTenor, 1);

for y = 1:maxTenor
    vanillaPaymentDates(y) = add_target_months(exerciseDate, 12 * y, 'modifiedfollow');
end

vanillaAccrualStarts = [exerciseDate; vanillaPaymentDates(1:end-1)];
vanillaYearFracs = yearfrac(vanillaAccrualStarts, vanillaPaymentDates, 2); % ACT/360

vanillaPaymentDFs = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, vanillaPaymentDates);
vanillaFwdDiscounts = vanillaPaymentDFs ./ optionDiscount;

vanillaBPVs = zeros(1, length(normalVol.tenorsNum));
for i = 1:length(normalVol.tenorsNum)
    idx = normalVol.tenorsNum(i); 
    vanillaBPVs(i) = sum(vanillaYearFracs(1:idx) .* vanillaFwdDiscounts(1:idx));
end

interpolated_sigma = interp1(vanillaBPVs, volsAtExpiry, ammortizedBPV, 'linear', 'extrap');

% =========================================================================
% Actual Swaption formula (Bachelier)
% =========================================================================
stdDev = interpolated_sigma * sqrt(TTM); 
d = (ammortizedFwdSwapRate - strike) / stdDev;
phi = exp(-0.5 * d^2) / sqrt(2*pi);
Phi = 0.5 * erfc(-d / sqrt(2));

if isPayer
    unitPrice = optionDiscount * ammortizedBPV * ((ammortizedFwdSwapRate - strike) * Phi + stdDev * phi);
else
    unitPrice = optionDiscount * ammortizedBPV * ((strike - ammortizedFwdSwapRate) * (1 - Phi) + stdDev * phi);
end
price = unitPrice * remainingNotional(1);
end