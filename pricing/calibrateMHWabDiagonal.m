function [aCal, bCal, sseMin, rmse] = calibrateMHWabDiagonal( ...
    OIS_curve, EUR3M_curve, diagData, gamma, isPayer)
%CALIBRATEMHWABDIAGONAL Calibra i parametri (a,b) del modello MHW a gamma fissato.
%
% Minimizza la funzione errore del paper (eq. 4.1):
%   Err2(a,b) = sum_i ( PriceModel_i(a,b,gamma) - PriceMkt_i )^2
% usando le sole diagonal swaptions.
% La ricerca del minimo globale viene gestita internamente con multi-start.
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
%   sseMin, rmse            Errore SSE e RMSE sui prezzi.

    if nargin < 5 || isempty(isPayer)
        isPayer = true;
    end

    % Internal calibration settings (always used).
    lb = [0, 0];
    ub = [];
    nRandomStarts = 10;
    nRefinementStarts = 3;
    randomSeed = 1234;
    anchorStarts = [ ...
        0.001, 0.005; ...
        0.010, 0.010; ...
        0.050, 0.015; ...
        0.100, 0.020; ...
        0.500, 0.100; ...
        2.500, 0.750; ...
        5.000, 1.500; ...
        10.00, 3.000; ...
        25.00, 8.000];
    
    mkt = diagData.summary;
    expiryYears = mkt.ExpiryYears(:);
    tenorYears = mkt.TenorYears(:);
    strikeATM = mkt.StrikeATM(:);
    marketPrices = mkt.MarketPrice(:);

    n = numel(expiryYears);
    settleDate = OIS_curve.settlementDate;

    opts = optimoptions('fmincon','Display','off','Algorithm','sqp', ...
        'StepTolerance',1e-9,'FunctionTolerance',1e-12, ...
        'MaxIterations',1200,'MaxFunctionEvaluations',2500);

    % Internal global search via multi-start (anchor starts + random starts).
    startSet = anchorStarts;
    if size(startSet, 2) ~= 2
        error('calibrateMHWabDiagonal:InvalidAnchorStarts', ...
            'anchorStarts must be an N-by-2 numeric matrix.');
    end
    rng(randomSeed, 'twister');
    randomStarts = generateRandomStarts(nRandomStarts, lb, ub);
    startSet = [startSet; randomStarts];
    startSet = unique(startSet, 'rows');

    % Screen all starts with one objective evaluation and refine only the best ones.
    screenSSE = zeros(size(startSet, 1), 1);
    for k = 1:size(startSet, 1)
        screenSSE(k) = objectiveAB(startSet(k, :).');
    end
    [~, order] = sort(screenSSE, 'ascend');
    kBest = min(nRefinementStarts, numel(order));
    startSet = startSet(order(1:kBest), :);

    xOpt = [NaN, NaN];
    sseMin = inf;
    for k = 1:size(startSet, 1)
        x0Try = clampToBounds(startSet(k, :), lb, ub);
        [xTry, sseTry] = fmincon(@objectiveAB, x0Try, [], [], [], [], lb, ub, [], opts);
        if sseTry < sseMin
            sseMin = sseTry;
            xOpt = xTry(:).';
        end
    end
    
    aCal = xOpt(1);
    bCal = xOpt(2);

    [modelPrices, flag] = modelPricesFromParams(aCal, bCal);
    if ~flag
        error('Model pricing failed at calibrated parameters.');
    end

    residuals = modelPrices - marketPrices;
    rmse = sqrt(mean(residuals.^2));


function sse = objectiveAB(x)
    aTry = x(1);
    bTry = x(2);

    [modelTry, flag] = modelPricesFromParams(aTry, bTry);
    if ~flag || any(~isfinite(modelTry))
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

function xOut = clampToBounds(xIn, lbIn, ubIn)
    xOut = xIn;
    if ~isempty(lbIn)
        xOut = max(xOut, lbIn);
    end
    if ~isempty(ubIn)
        xOut = min(xOut, ubIn);
    end
end

function starts = generateRandomStarts(nStarts, lbIn, ubIn)
    if nStarts <= 0
        starts = zeros(0, 2);
        return;
    end

    if isempty(ubIn)
        % No upper bounds: sample on a log scale to explore both small and very large values.
        aMin = 1e-4; aMax = 1e2;
        bMin = 1e-4; bMax = 1e2;
        ua = rand(nStarts, 1);
        ub = rand(nStarts, 1);
        starts = zeros(nStarts, 2);
        starts(:,1) = 10.^(log10(aMin) + ua .* (log10(aMax) - log10(aMin)));
        starts(:,2) = 10.^(log10(bMin) + ub .* (log10(bMax) - log10(bMin)));
        starts = max(starts, lbIn);
        return;
    end

    lbEff = lbIn;
    ubEff = ubIn;
    u = rand(nStarts, 2);
    starts = lbEff + u .* (ubEff - lbEff);
end

end
