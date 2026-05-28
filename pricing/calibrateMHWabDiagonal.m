function [aCal, bCal, calib] = calibrateMHWabDiagonal( ...
    OIS_curve, EUR3M_curve, diagData, gamma, isPayer)
%CALIBRATEMHWABDIAGONAL Calibra i parametri (a,b) del modello MHW a gamma fissato.
%
% Minimizza la funzione errore del paper (eq. 4.1):
%   Err2(a,b) = sum_i ( PriceModel_i(a,b,gamma) - PriceMkt_i )^2
% usando le sole diagonal swaptions.
%
% INPUT
%   OIS_curve, EUR3M_curve  Curve bootstrap (struct).
%   diagData                Struct output di buildDiagonalSwaptionMarketData
%                           con campo .summary (tabella con colonne:
%                           ExpiryYears, TenorYears, StrikeATM, MarketPrice).
%   gamma                   Parametro gamma fissato in [0,1].
%   isPayer                 true/false (default true).
%
% OUTPUT
%   aCal, bCal              Parametri calibrati.
%   calib                   Struct con diagnostica e tabella risultati.

    if nargin < 5 || isempty(isPayer)
        isPayer = true;
    end

    if gamma < 0 || gamma > 1
        error('calibrateMHWabDiagonal:GammaOutOfRange', ...
            'gamma must be in [0,1].');
    end

    if ~isstruct(diagData) || ~isfield(diagData, 'summary')
        error('calibrateMHWabDiagonal:InvalidMarketData', ...
            'diagData must be a struct with field .summary.');
    end

    % Initial guess
    x0 = [0.1, 0.1];
    
    mkt = diagData.summary;
    expiryYears = mkt.ExpiryYears(:);
    tenorYears = mkt.TenorYears(:);
    strikeATM = mkt.StrikeATM(:);
    marketPrices = mkt.MarketPrice(:);

    n = numel(expiryYears);
    settleDate = OIS_curve.settlementDate;

    % Constrained optimization: enforce a,b > 0 with lower bounds.
    lb = [eps, eps];
    ub = [];
    
    opts = optimoptions('fmincon','Display','off','Algorithm','sqp', ...
        'StepTolerance',1e-9,'FunctionTolerance',1e-12, ...
        'MaxIterations',3000,'MaxFunctionEvaluations',10000);

    [xOpt, sseMin] = fmincon(@objectiveAB, x0, [], [], [], [], lb, ub, [], opts);
    
    aCal = xOpt(1);
    bCal = xOpt(2);

    [modelPrices, ok] = modelPricesFromParams(aCal, bCal);
    if ~ok
        error('calibrateMHWabDiagonal:PricingFailureAtOptimum', ...
              'Model pricing failed at calibrated parameters.');
    end

    residuals = modelPrices - marketPrices;
    absErrors = abs(residuals);
    rmse = sqrt(mean(residuals.^2));

    resultsTable = table(expiryYears, tenorYears, strikeATM, marketPrices, ...
        modelPrices, residuals, absErrors, ...
        'VariableNames', {'ExpiryYears','TenorYears','StrikeATM', ...
                          'MarketPrice','ModelPrice','Residual','AbsError'});

    calib = struct();
    calib.a = aCal;
    calib.b = bCal;
    calib.gamma = gamma;
    calib.sse = sseMin;
    calib.rmse = rmse;
    calib.marketPrices = marketPrices;
    calib.modelPrices = modelPrices;
    calib.residuals = residuals;
    calib.resultsTable = resultsTable;



function sse = objectiveAB(x)
    aTry = x(1);
    bTry = x(2);

    [modelTry, okTry] = modelPricesFromParams(aTry, bTry);
    if ~okTry || any(~isfinite(modelTry))
        sse = 1e30;
        return;
    end

    r = modelTry - marketPrices;
    sse = sum(r.^2);
    if ~isfinite(sse)
        sse = 1e30;
    end
end

function [modelVec, flag] = modelPricesFromParams(aTry, bTry)
    modelVec = zeros(n, 1);
    flag = true;

    for i = 1:n
        try
            exDate = add_target_months(settleDate, round(12 * expiryYears(i)), 'modifiedfollow');
            matDate = add_target_months(exDate, round(12 * tenorYears(i)), 'modifiedfollow');
            % Task 5 convention: floating quarterly, fixed annual.
            floatSched = makeSchedule(exDate, matDate, 3, 'modifiedfollow');
            % floatSched = makeSchedule(exDate, matDate, 6, 'modifiedfollow'); % Paper requires Euribor 6m floating frequency.
            % DIPENDE DA COSA RIPONDE NELLA MAIL
            fixedSched = makeSchedule(exDate, matDate, 12, 'modifiedfollow');
            floatPayDates = floatSched(2:end);
            fixedPayDates = fixedSched(2:end);

            modelVec(i) = model_multiHJM_Price( ...
                OIS_curve, EUR3M_curve, floatPayDates, fixedPayDates, ...
                strikeATM(i), expiryYears(i), aTry, bTry, gamma, isPayer);
        catch
            flag = false;
            return;
        end
    end
end



end