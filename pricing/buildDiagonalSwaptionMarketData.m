function diagData = buildDiagonalSwaptionMarketData( ...
    OIS_curve, EUR3M_curve, diagSwaptionsTable, isPayer, isCS)
    
%BUILDDIAGONALSWAPTIONMARKETDATA
% Build market dataset on diagonal swaptions:
% Convenzione usata
%   - floating leg: quarterly (fissa)
%   - fixed leg: annual
%
% INPUT:
%   OIS_curve, EUR3M_curve     curve structs
%   diagSwaptionsTable         table with columns: Expiry, Tenor, NormalVol_bps
%   isPayer                    true/false (default true)
%   isCS                       true = Cash-Settled convention,
%                              false = Physical Delivery convention (default true for Task 5)
%
% OUTPUT:
%   diagData.summary           compact table with calibration inputs

    if nargin < 4 || isempty(isPayer)
        isPayer = true;
    end
    if nargin < 5 || isempty(isCS)
        isCS = true;
    end

    % Preallocation
    n = height(diagSwaptionsTable);
    settlementDate = OIS_curve.settlementDate;

    % Vectorized parsing of diagonal labels and market normal vols
    expiryYears = str2double(erase(lower(string(diagSwaptionsTable.Expiry(:))), "y"));
    tenorYears  = str2double(erase(lower(string(diagSwaptionsTable.Tenor(:))),  "y"));
    volSwap     = diagSwaptionsTable.NormalVol_bps(:) ./ 10000.0;

    % Vectorized computation of option expiry and underlying swap maturity
    expiryDates = arrayfun(@(y) add_target_months(settlementDate, round(12 * y), 'modifiedfollow'), expiryYears);
    maturityDates = arrayfun(@(e,t) add_target_months(e, round(12 * t), 'modifiedfollow'), expiryDates, tenorYears);

    strikeATM = zeros(n,1);
    annuityFwd = zeros(n,1);
    dfExpiry = zeros(n,1);
    marketPrice = zeros(n,1);

    % Loop only where full vectorization is not practical:
    % each swaption has its own coupon schedule length.
    for i = 1:n
        % Underlying swap schedules: floating and fixed with distinct frequencies.
        floatStepMonths = 3;
        floatSched = makeSchedule(expiryDates(i), maturityDates(i), floatStepMonths, 'modifiedfollow');
        fixedSched = makeSchedule(expiryDates(i), maturityDates(i), 12, 'modifiedfollow');

        floatPaymentDates = floatSched(2:end);            % remove start date
        fixedPaymentDates = fixedSched(2:end);            % remove start date
        notionals = ones(numel(floatPaymentDates), 1);    % unit notional (calibration scale)

        % Extract ATM forward quantities (S0, A, P0T) from curves.
        [~, qATM] = bachelierPSSwaptionPricerDiagonal( ...
            OIS_curve, EUR3M_curve, floatPaymentDates, fixedPaymentDates, 0.0, 0.0, ...
            expiryYears(i), notionals, isPayer, "quarterly", isCS);

        K = qATM.forwardSwapRate;                         % ATM strike K = S0

        strikeATM(i) = K;
        annuityFwd(i) = qATM.annuityFwd;
        dfExpiry(i) = qATM.optionDiscount;

        % ATM Bachelier price:
        % V_ATM = P(0,T) * A_fwd(0) * sigma_N * sqrt(T) / sqrt(2*pi)
        TTM_act365 = yearfrac(settlementDate, expiryDates(i), 3);
        marketPrice(i) = dfExpiry(i) * annuityFwd(i) * volSwap(i) * ...
            sqrt(TTM_act365) / sqrt(2*pi);
    end

    summary = table( expiryYears, tenorYears, volSwap, ...
        strikeATM, annuityFwd, dfExpiry, marketPrice, ...
        'VariableNames', {'ExpiryYears','TenorYears', 'NormalVol', ...
                          'StrikeATM','AnnuityFwd','DF_Expiry','MarketPrice'});
    diagData = struct();
    diagData.referenceDate = settlementDate;
    diagData.summary = summary;
end
