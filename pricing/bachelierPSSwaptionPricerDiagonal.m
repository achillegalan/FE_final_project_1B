function [price, details] = bachelierPSSwaptionPricerDiagonal( ...
    OIS_curve, EUR3M_curve, floatingPaymentDates, fixedPaymentDates, ...
    strike, normalVol, TTM, Notional, isPayer, fixingFrequency, isCS)
%BACHELIERPSSWAPTIONPRICERDIAGONAL Prices a European swaption using the
% market-standard Bachelier (normal) framework in a multi-curve setting.
%
% INPUT
%   OIS_curve             Struct containing the OIS curve used for discounting.
%   EUR3M_curve           Struct containing the Euribor 3M pseudo-discount curve.
%   floatingPaymentDates  Vector of floating-leg payment dates.
%   fixedPaymentDates     Vector of fixed-leg payment dates.
%   strike                Swaption strike, i.e. the fixed rate of the underlying swap.
%   normalVol             Market normal (Bachelier) volatility.
%   TTM                   Time to maturity of the swaption, expressed in years.
%   Notional              Scalar notional or amortizing notional vector.
%   isPayer               Boolean flag: true for payer swaption, false for receiver.
%   fixingFrequency       Floating reset frequency: "quarterly" or "semiannual".
%   isCS                  Boolean flag: true for cash-settled, false for physical-delivery.
%
% OUTPUT
%   price                 Swaption price obtained from the Bachelier formula.
%   details               Struct containing intermediate pricing quantities,
%                         including forward swap rate, annuity, discount factor,
%                         standard deviation, accrual fractions and payment schedules.

    if nargin < 9 || isempty(isPayer)
        isPayer = true;
    end
    if nargin < 10 || isempty(fixingFrequency)
        fixingFrequency = "quarterly";
    end

    floatingPaymentDates = floatingPaymentDates(:);
    fixedPaymentDates = fixedPaymentDates(:);
    Notional = Notional(:);

    settleDate = OIS_curve.settlementDate;
    exerciseDate = add_target_months(settleDate, round(12 * TTM), 'modifiedfollow');

    nFloatIn = numel(floatingPaymentDates);
    if isempty(Notional)
        error('bachelierPSSwaptionPricerDiagonal:InvalidNotional', 'Notional cannot be empty.');
    elseif numel(Notional) == 1
        notionalFloatAll = repmat(Notional, nFloatIn, 1);
    elseif numel(Notional) == nFloatIn
        notionalFloatAll = Notional;
    else
        error('bachelierPSSwaptionPricerDiagonal:NotionalSizeMismatch', ...
            'Notional must be scalar or have same length as floatingPaymentDates.');
    end

    % Keep only coupons strictly after option expiry.
    remainingFloat = floatingPaymentDates > exerciseDate;
    floatingPaymentDates = floatingPaymentDates(remainingFloat);
    remainingNotionalFloat = notionalFloatAll(remainingFloat);

    fixedPaymentDates = fixedPaymentDates(fixedPaymentDates > exerciseDate);

    if isempty(floatingPaymentDates) || isempty(fixedPaymentDates)
        price = 0;
        details = struct();
        details.exerciseDate = exerciseDate;
        details.remainingNotional = [];
        details.yearFracs = [];
        details.optionDiscount = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, exerciseDate);
        details.annuityFwd = 0;
        details.forwardSwapRate = 0;
        details.strike = strike;
        details.normalVol = normalVol;
        details.stdDev = normalVol * sqrt(max(TTM, 0));
        return;
    end

    [isFixedOnFloatGrid, fixedIdxOnFloat] = ismember(fixedPaymentDates, floatingPaymentDates);
    if ~all(isFixedOnFloatGrid)
        error('bachelierPSSwaptionPricerDiagonal:FixedDatesNotOnFloatingGrid', ...
            'Each fixed payment date must belong to the floating payment schedule.');
    end

    % Accrual fractions (ACT/360) for floating and fixed coupons.
    floatAccrualStartDates = [exerciseDate; floatingPaymentDates(1:end-1)];
    floatYearFracs = yearfrac(floatAccrualStartDates, floatingPaymentDates, 2);

    fixedAccrualStartDates = [exerciseDate; fixedPaymentDates(1:end-1)];
    fixedYearFracs = yearfrac(fixedAccrualStartDates, fixedPaymentDates, 1); % Paper requires 30/360 for the fixed leg day-count.

    % Discounting to expiry-forward measure.
    optionDiscount = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, exerciseDate);
    floatPaymentDiscounts = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, floatingPaymentDates);
    floatFwdDiscounts = floatPaymentDiscounts ./ optionDiscount;

    fixedPaymentDiscounts = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, fixedPaymentDates);
    fixedFwdDiscounts = fixedPaymentDiscounts ./ optionDiscount;

    % Projection from pseudo-discount curve (3M / selected floating frequency).
    pseudoDiscounts = getTargetDF(settleDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, floatingPaymentDates);
    pseudoAtExpiry = getTargetDF(settleDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, exerciseDate);
    pseudoFull = [pseudoAtExpiry; pseudoDiscounts];

    floatFwdRates = (pseudoFull(1:end-1) ./ pseudoFull(2:end) - 1) ./ floatYearFracs;

    if fixingFrequency == "semiannual"
        fixingRates = floatFwdRates;
        fixingRates(2:2:end) = floatFwdRates(1:2:end-1);
    else
        fixingRates = floatFwdRates;
    end

    % Amortized forward annuity and forward swap rate.
    amortizedNotionalFloat = remainingNotionalFloat ./ remainingNotionalFloat(1);
    amortizedNotionalFixed = amortizedNotionalFloat(fixedIdxOnFloat);

    annuityFwd = sum(fixedYearFracs .* amortizedNotionalFixed .* fixedFwdDiscounts);

    floatLegFwdValue = sum(floatFwdDiscounts .* floatYearFracs .* ...
                           amortizedNotionalFloat .* fixingRates);
    forwardSwapRate = floatLegFwdValue / annuityFwd;

    if isCS
        nTenor = length(fixedPaymentDates); % same convention as model_multiHJM_Price
        if abs(forwardSwapRate) < 1e-12
            annuityFwd = nTenor;
        else
            annuityFwd = (1 - (1 + forwardSwapRate)^(-nTenor)) / forwardSwapRate;
        end
    end

    %% Bachelier closed-form.
    w = 2 * double(isPayer) - 1;        % +1 payer, -1 receiver
    stdDev = normalVol * sqrt(TTM);

    if stdDev <= eps
        intrinsic = max(w * (forwardSwapRate - strike), 0);
        price = optionDiscount * annuityFwd * intrinsic;
    else
        d = (forwardSwapRate - strike) / stdDev;
        phi = exp(-0.5 * d^2) / sqrt(2*pi);
        Nwd = 0.5 * erfc(-(w * d) / sqrt(2));   % N(w*d)
        price = optionDiscount * annuityFwd * (w * (forwardSwapRate - strike) * Nwd + stdDev * phi);
    end

    details = struct();
    details.exerciseDate = exerciseDate;
    details.remainingNotional = remainingNotionalFloat;
    details.yearFracs = floatYearFracs;
    details.fixedYearFracs = fixedYearFracs;
    details.optionDiscount = optionDiscount;
    details.annuityFwd = annuityFwd;
    details.forwardSwapRate = forwardSwapRate;
    details.strike = strike;
    details.normalVol = normalVol;
    details.stdDev = stdDev;
    details.floatingPaymentDates = floatingPaymentDates;
    details.fixedPaymentDates = fixedPaymentDates;
    details.fixedIdxOnFloat = fixedIdxOnFloat;
end
