function [aCal, bCal, calib] = calibrateMHWabDiagonal( ...
    OIS_curve, EUR3M_curve, diagData, gamma, isPayer, isCS)
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
%   isCS                    true for cash settle, false for physical delivery
%                           (default true).
%
% OUTPUT
%   aCal, bCal              Parametri calibrati.
%   calib                   Struct con diagnostica e tabella risultati.

    if nargin < 5 || isempty(isPayer)
        isPayer = true;
    end
    if nargin < 6 || isempty(isCS)
        isCS = true;
    end

    % Initial guesses: multi-start calibration
    x0List = [  0.1, 0.1;
                0.08, 0.015 ];
        
    mkt = diagData.summary;
    expiryYears = mkt.ExpiryYears(:);
    tenorYears = mkt.TenorYears(:);
    strikeATM = mkt.StrikeATM(:);
    marketPrices = mkt.MarketPrice(:);

    n = numel(expiryYears);
    settleDate = OIS_curve.settlementDate;
    
    % Cache schedule-related objects that do not depend on (a,b).
    floatPayDatesCache = cell(n, 1);
    fixedPayDatesCache = cell(n, 1);
    for i = 1:n
        exDate = add_target_months(settleDate, round(12 * expiryYears(i)), 'modifiedfollow');
        matDate = add_target_months(exDate, round(12 * tenorYears(i)), 'modifiedfollow');
        % Task 5 convention: floating quarterly, fixed annual.
        floatSched = makeSchedule(exDate, matDate, 3, 'modifiedfollow');
        fixedSched = makeSchedule(exDate, matDate, 12, 'modifiedfollow');
        floatPayDatesCache{i} = floatSched(2:end);
        fixedPayDatesCache{i} = fixedSched(2:end);
    end

    % Constrained optimization: enforce a,b > 0 with lower bounds.
    lb = [0, eps];
    ub = [0.4, 0.4];
    
    opts = optimoptions('fmincon','Display','off','Algorithm','sqp', ...
        'StepTolerance',1e-9,'FunctionTolerance',1e-15, ...
        'MaxIterations',2500,'MaxFunctionEvaluations',10000);

    nStarts = size(x0List, 1);
    xOptAll = zeros(nStarts, 2);
    sseAll = inf(nStarts, 1);
    exitflagAll = zeros(nStarts, 1);
    
    for k = 1:nStarts
        x0 = x0List(k, :);
    
        try
            [xOptAll(k, :), sseAll(k), exitflagAll(k)] = fmincon( ...
                @objectiveAB, x0, [], [], [], [], lb, ub, [], opts);
        catch
            sseAll(k) = inf;
            exitflagAll(k) = NaN;
        end
    end
    
    [sseMin, bestIdx] = min(sseAll);
    
    if ~isfinite(sseMin)
        error('calibrateMHWabDiagonal:MultiStartFailure', ...
              'All fmincon multi-start calibrations failed.');
    end
    
    xOpt = xOptAll(bestIdx, :);
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
            floatPayDates = floatPayDatesCache{i};
            fixedPayDates = fixedPayDatesCache{i};

            modelVec(i) = model_multiHJM_Price( ...
                OIS_curve, EUR3M_curve, floatPayDates, fixedPayDates, ...
                strikeATM(i), expiryYears(i), aTry, bTry, gamma, isPayer, isCS);
        catch
            flag = false;
            return;
        end
    end
end

end

