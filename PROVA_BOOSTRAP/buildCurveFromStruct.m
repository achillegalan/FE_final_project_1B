function curve = buildCurveFromStruct(mkt, settlementDate)
%BUILDCURVEFROMSTRUCT Build curve object from imported struct.
%
% This does not bootstrap.
% It simply converts your already imported terms, discounts, and zero rates
% into a usable curve object.
% INPUTS:
%   mkt            - Structure returned by importMarketData, containing the
%                    fields Term, Discount, and ZeroRate.
%   settlementDate - Datetime object representing the curve settlement date.
%
% OUTPUTS:
%   curve - Structure containing the converted curve data:
%           settlementDate - Curve settlement date.
%           terms          - Market terms as strings.
%           dates          - Adjusted maturity dates.
%           discounts      - Discount factors sorted by date.
%           zeroRates      - Continuously-compounded zero rates.
%           table          - Table with Date, Discount, and ZeroRate columns.

    terms = string(mkt.Term(:));

    dates = convertTermToDays(terms, settlementDate);

    curve.settlementDate = settlementDate;
    curve.terms = terms;
    curve.dates = dates;
    curve.discounts = mkt.Discount(:);
    curve.zeroRates = mkt.ZeroRate(:);

    [curve.dates, curve.discounts] = sortCurve(curve.dates, curve.discounts);

    tau = yearfrac(settlementDate, curve.dates, 3);
    curve.zeroRates = -log(curve.discounts) ./ tau;

    curve.table = table(curve.dates, curve.discounts, curve.zeroRates, ...
        'VariableNames', {'Date','Discount','ZeroRate'});
end
