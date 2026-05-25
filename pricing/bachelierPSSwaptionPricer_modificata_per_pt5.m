function [price, details] = bachelierPSSwaptionPricer_modificata_per_pt5( ...
    OIS_curve, EUR3M_curve, paymentDates, strike, normalVol, TTM, Notional, isPayer, fixingFrequency)
%BACHELIERPSSWAPTIONPRICER Physical-settlement swaption under Bachelier.
%
% Price formula (normal model):
%   V0 = P(0,Texp)*A_fwd(0) * [ w*(S0-K)*N(w*d) + sigmaN*sqrt(Texp)*phi(d) ]
% where w=+1 payer, w=-1 receiver, d=(S0-K)/(sigmaN*sqrt(Texp)).
%
% INPUTS:
%   OIS_curve       struct with fields: settlementDate, dates, zeroRates
%   EUR3M_curve     struct with fields: dates, zeroRates
%   paymentDates    payment dates of underlying swap (column/row vector)
%   strike          fixed rate K
%   normalVol       Bachelier normal vol (decimal, e.g. 80 bps = 0.0080)
%   TTM             option expiry in years (from settlementDate)
%   Notional        notionals (same length as paymentDates)
%   isPayer         true= payer (call), false= receiver (put)
%   fixingFrequency 'quarterly' or 'semiannual' (also accepts logical:
%                   true=semiannual, false=quarterly)
%
% OUTPUTS:
%   price           time-0 swaption price
%   details         struct with forward quantities used in pricing

    if nargin < 8 || isempty(isPayer)
        isPayer = true;
    end
    if nargin < 9 || isempty(fixingFrequency)
        fixingFrequency = "quarterly";
    end

    paymentDates = paymentDates(:);
    Notional = Notional(:);

    settleDate = OIS_curve.settlementDate;
    exerciseDate = add_target_months(settleDate, round(12 * TTM), 'modifiedfollow');

    % Keep only coupons strictly after option expiry.
    remaining = paymentDates > exerciseDate;
    paymentDates = paymentDates(remaining);
    remainingNotional = Notional(remaining);

    % Accrual fractions (ACT/360) for underlying coupons.
    accrualStartDates = [exerciseDate; paymentDates(1:end-1)];
    yearFracs = yearfrac(accrualStartDates, paymentDates, 2);

    % Discounting to expiry-forward measure.
    optionDiscount = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, exerciseDate);
    paymentDiscounts = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, paymentDates);
    fwdDiscounts = paymentDiscounts ./ optionDiscount;

    % Projection from pseudo-discount curve (3M).
    pseudoDiscounts = getTargetDF(settleDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, paymentDates);
    pseudoAtExpiry = getTargetDF(settleDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, exerciseDate);
    pseudoFull = [pseudoAtExpiry; pseudoDiscounts];

    quarterlyFwdRates = (pseudoFull(1:end-1) ./ pseudoFull(2:end) - 1) ./ yearFracs;

    if fixingFrequency == "semiannual"
        fixingRates = quarterlyFwdRates;
        fixingRates(2:2:end) = quarterlyFwdRates(1:2:end-1);
    else
        fixingRates = quarterlyFwdRates;
    end

    % Amortized forward annuity and forward swap rate.
    % COMMENT: N_alpha in the formula I am pretty sure is the first notional
    % available (as Locatelli actually told us I believe during the call, but
    % also as suggested by notation explanation in the PDF file)
    amortizedNotional = remainingNotional ./ remainingNotional(1);
    annuityFwd = sum(yearFracs .* amortizedNotional .* fwdDiscounts);

    floatLegFwdValue = sum(fwdDiscounts .* yearFracs .* amortizedNotional .* fixingRates);
    forwardSwapRate = floatLegFwdValue / annuityFwd;

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
    details.remainingNotional = remainingNotional;
    details.yearFracs = yearFracs;
    details.optionDiscount = optionDiscount;
    details.annuityFwd = annuityFwd;
    details.forwardSwapRate = forwardSwapRate;
    details.strike = strike;
    details.normalVol = normalVol;
    details.stdDev = stdDev;
end